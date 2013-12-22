## Code modified from 
## http://chromeos-cr48.blogspot.com/2013/05/chrubuntu-one-script-to-rule-them-all_31.html
# fw_type will always be developer for Mario.
# Alex and ZGB need the developer BIOS installed though.

# Check we're in dev mode.
fw_type="`crossystem mainfw_type`"
if [ ! "$fw_type" = "developer" ]
  then
    echo -e "\nYou're Chromebook is not running a developer BIOS!"
    echo -e "You need to run:"
    echo -e ""
    echo -e "sudo chromeos-firmwareupdate --mode=todev"
    echo -e ""
    echo -e "and then re-run this script."
    exit 
fi

# Keep display on.
powerd_status="`initctl status powerd`"
if [ ! "$powerd_status" = "powerd stop/waiting" ]
then
  echo -e "Stopping powerd to keep display from timing out..."
  initctl stop powerd
fi
setterm -blank 0

# Write changes to disk
if [ "$3" != "" ]; then
  target_disk=$3
  echo "Got ${target_disk} as target drive"
  echo ""
  echo "WARNING! All data on this device will be wiped out! Continue at your own risk!"
  echo ""
  read -p "Press [Enter] to install ChromeArch on ${target_disk} or CTRL+C to quit"

  ext_size="`blockdev --getsz ${target_disk}`"
  aroot_size=$((ext_size - 65600 - 33))
  parted --script ${target_disk} "mktable gpt"
  cgpt create ${target_disk} 
  cgpt add -i 6 -b 64 -s 32768 -S 1 -P 5 -l KERN-A -t "kernel" ${target_disk}
  cgpt add -i 7 -b 65600 -s $aroot_size -l ROOT-A -t "rootfs" ${target_disk}
  sync
  blockdev --rereadpt ${target_disk}
  partprobe ${target_disk}
  crossystem dev_boot_usb=1
else
  #Prompt user for disk sizes
  target_disk="`rootdev -d -s`"
  # Do partitioning (if we haven't already)
  ckern_size="`cgpt show -i 6 -n -s -q ${target_disk}`"
  croot_size="`cgpt show -i 7 -n -s -q ${target_disk}`"
  state_size="`cgpt show -i 1 -n -s -q ${target_disk}`"

  max_arch_size=$(($state_size/1024/1024/2))
  rec_arch_size=$(($max_arch_size - 1))
  # If KERN-C and ROOT-C are one, we partition, otherwise assume they're what they need to be...
  if [ "$ckern_size" =  "1" -o "$croot_size" = "1" ]
  then
    while :
    do
      read -p "Enter the size in gigabytes you want to reserve for arch. Acceptable range is 5 to $max_arch_size  but $rec_arch_size is the recommended maximum: " arch_size
      if [ ! $arch_size -ne 0 2>/dev/null ]
      then
        echo -e "\n\nNumbers only please...\n\n"
        continue
      fi
      if [ $arch_size -lt 5 -o $arch_size -gt $max_arch_size ]
      then
        echo -e "\n\nThat number is out of range. Enter a number 5 through $max_arch_size\n\n"
        continue
      fi
      break
    done
    # We've got our size in GB for ROOT-C so do the math...

    #calculate sector size for rootc
    rootc_size=$(($arch_size*1024*1024*2))

    #kernc is always 16mb
    kernc_size=32768

    #new stateful size with rootc and kernc subtracted from original
    stateful_size=$(($state_size - $rootc_size - $kernc_size))

    #start stateful at the same spot it currently starts at
    stateful_start="`cgpt show -i 1 -n -b -q ${target_disk}`"

    #start kernc at stateful start plus stateful size
    kernc_start=$(($stateful_start + $stateful_size))

    #start rootc at kernc start plus kernc size
    rootc_start=$(($kernc_start + $kernc_size))

    #Do the real work

    echo -e "\n\nModifying partition table to make room for arch." 
    echo -e "Your Chromebook will reboot, wipe your data and then"
    echo -e "you should re-run this script..."
    umount -f /mnt/stateful_partition

    # stateful first
    cgpt add -i 1 -b $stateful_start -s $stateful_size -l STATE ${target_disk}

    # now kernc
    cgpt add -i 6 -b $kernc_start -s $kernc_size -l KERN-C ${target_disk}

    # finally rootc
    cgpt add -i 7 -b $rootc_start -s $rootc_size -l ROOT-C ${target_disk}

    reboot
    exit
  fi
fi

# hwid lets us know if this is a Mario (Cr-48), Alex (Samsung Series 5), ZGB (Acer), etc
hwid="`crossystem hwid`"
chromebook_arch="`uname -m`"
arch_version="default"

echo -e "\nChrome device model is: $hwid\n"

echo -e "Attempting to pacstrap Arch Linux\n"
echo -e "Kernel Arch is: $chromebook_arch  Installing Arch:\n"
read -p "Press [Enter] to continue..."

if [ ! -d /mnt/stateful_partition/arch ]
then
  mkdir /mnt/stateful_partition/arch
fi

cd /mnt/stateful_partition/arch

# If on arm we need a p before the partition #
if [[ "${target_disk}" =~ "mmcblk" ]]
then
  target_rootfs="${target_disk}p7"
  target_kern="${target_disk}p6"
else
  target_rootfs="${target_disk}7"
  target_kern="${target_disk}6"
fi

echo "Target Kernel Partition: $target_kern  Target Root FS: ${target_rootfs}"

if mount|grep ${target_rootfs}
then
  echo "Refusing to continue since ${target_rootfs} is formatted and mounted. Try rebooting"
  exit 
fi

# Format rootfs to ext4
mkfs.ext4 ${target_rootfs}

# Mount new root
if [ ! -d /tmp/archfs ]
then
  mkdir /tmp/archfs
fi
mount -t ext4 ${target_rootfs} /tmp/archfs

# pacstrap arch Get OS Image and extract to root. 
## TODO

# We're about to chroot: remount.
mount -o bind /proc /tmp/archfs/proc
mount -o bind /dev /tmp/archfs/dev
mount -o bind /dev/pts /tmp/archfs/dev/pts
mount -o bind /sys /tmp/archfs/sys

# Grab a copy of cgpt for our new install.
if [ -f /usr/bin/old_bins/cgpt ]
then
  cp /usr/bin/old_bins/cgpt /tmp/archfs/usr/bin/
else
  cp /usr/bin/cgpt /tmp/archfs/usr/bin/
fi
chmod a+rx /tmp/archfs/usr/bin/cgpt

# Set hostname vars.
cp /etc/resolv.conf /tmp/archfs/etc/
echo ChromeArch > /tmp/archfs/etc/hostname
#echo -e "127.0.0.1       localhost
echo -e "\n127.0.1.1       ChromeArch" >> /tmp/archfs/etc/hosts

# System updates for ubuntu TODO switch to arch
echo -e "
## TODO LIST
#copy modules

#reset hostname
#install base & base-devel
#install wl & wpa_supp
#turn off touch pad wakeup
#cgpt set successful 

" > /tmp/archfs/install-arch.sh

# chroot and run install/update script.
chmod a+x /tmp/archfs/install-arch.sh
chroot /tmp/archfs /bin/bash -c /install-arch.sh
rm /tmp/archfs/install-arch.sh


# Prepare our kernel 
KERN_VER=`uname -r`
mkdir -p /tmp/archfs/lib/modules/$KERN_VER/
cp -ar /lib/modules/$KERN_VER/* /tmp/archfs/lib/modules/$KERN_VER/
if [ ! -d /tmp/archfs/lib/firmware/ ]
then
  mkdir /tmp/archfs/lib/firmware/
fi
# Copy over lib/firmware
cp -ar /lib/firmware/* /tmp/archfs/lib/firmware/

echo "console=tty1 debug verbose root=${target_rootfs} rootwait rw lsm.module_locking=0" > kernel-config
vbutil_arch="x86"
if [ $arch_arch = "armhf" ]
then
  vbutil_arch="arm"
fi

current_rootfs="`rootdev -s`"
current_kernfs_num=$((${current_rootfs: -1:1}-1))
current_kernfs=${current_rootfs: 0:-1}$current_kernfs_num

# Sign kernel so it will boot
vbutil_kernel --repack ${target_kern} \
    --oldblob $current_kernfs \
    --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
    --version 1 \
    --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
    --config kernel-config \
    --arch $vbutil_arch

#Set arch kernel partition as top priority for next boot (and next boot only)
cgpt add -i 6 -P 5 -T 1 ${target_disk}

# We're done, prompt user.
echo -e "

Installation seems to be complete. If ChromeArch fails to boot when you reboot,
power off your Chrome OS device and then turn it back on. You'll be back
in Chrome OS. If you're happy with ChromeArch when you reboot be sure to run:

sudo cgpt add -i 6 -P 5 -S 1 ${target_disk}

To make it the default boot option. The ChromeArch login is:

Username:  root
Password:  [blank]

We're now ready to start ChromeArch!
"

read -p "Press [Enter] to reboot..."

reboot