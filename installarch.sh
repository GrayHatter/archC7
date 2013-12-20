#This code was modified from chromeos-cr48.blogspot.com
usage()
{
cat << EOF
usage: $0 options

ArchLinux installation script.

OPTIONS:
   -h      show help.
   -a      Architecture to install (i386, amd64). Default is amd64 (64-bit).
   -t      Target drive to install to (/dev/mmcblk1, /dev/sdb, etc). Default is the builtin SSD.
EOF
}

target_disk=""
arch_arch="amd64"
arch_metapackage="arch-desktop"
arch_version="latest"
while getopts "hm:a:t:u:" OPTION
do
     case $OPTION in
         h)
             usage
             exit
             ;;
         a)
             arch_arch=$OPTARG
             ;;
         t)
             target_disk=$OPTARG
             ;;
         ?)
             usage
             exit
             ;;
     esac
done

echo "Determining support for legacy boot..."
LEGACY_LOCATION="`mosys -k eeprom map | grep RW_LEGACY`"
if [ "$LEGACY_LOCATION" = "" ]; then
  echo "Error: this Chrome device does not seem to support CTRL+L Legacy SeaBIOS booting. This script dosen't support this system. Sorry!"
  exit 1
fi
echo "This system supports legacy boot. Good."

powerd_status="`initctl status powerd`"
if [ ! "$powerd_status" = "powerd stop/waiting" ]
then
  echo -e "Stopping powerd to keep display from timing out..."
  initctl stop powerd
fi

setterm -blank 0

if [ "$target_disk" != "" ]; then
  echo "Got ${target_disk} as target drive"
  echo ""
  echo "WARNING! All data on this device will be wiped out! Continue at your own risk!"
  echo ""
  read -p "Press [Enter] to install ArchLinux on ${target_disk} or CTRL+C to quit"

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

    echo -e "\n\nModifying partition table to make room for ArchLinux."
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

if [ "$arch_version" = "lts" ]
then
  arch_version=`wget --quiet -O - http://changelogs.arch.com/meta-release | grep "^Version:" | grep "LTS" | tail -1 | sed -r 's/^Version: ([^ ]+)( LTS)?$/\1/'`
  tar_file="http://cdimage.arch.com/arch-core/releases/$arch_version/release/arch-core-$arch_version-core-$arch_arch.tar.gz"
elif [ "$arch_version" = "latest" ]
then
  arch_version=`wget --quiet -O - http://changelogs.arch.com/meta-release | grep "^Version: " | tail -1 | sed -r 's/^Version: ([^ ]+)( LTS)?$/\1/'`
  tar_file="http://cdimage.arch.com/arch-core/releases/$arch_version/release/arch-core-$arch_version-core-$arch_arch.tar.gz"
elif [ $arch_version = "dev" ]
then
  arch_version=`wget --quiet -O - http://changelogs.arch.com/meta-release-development | grep "^Version: " | tail -1 | sed -r 's/^Version: ([^ ]+)( LTS)?$/\1/'`
  arch_animal=`wget --quiet -O - http://changelogs.arch.com/meta-release-development | grep "^Dist: " | tail -1 | sed -r 's/^Dist: (.*)$/\1/'`
  tar_file="http://cdimage.arch.com/arch-core/daily/current/$arch_animal-core-$arch_arch.tar.gz"
fi

echo -e "\nChrome device model is: $hwid\n"

echo -e "Installing arch ${arch_version} with metapackage ${arch_metapackage}\n"

echo -e "Installing arch Arch: $arch_arch\n"

read -p "Press [Enter] to continue..."

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

mkfs.ext4 ${target_rootfs}

if [ ! -d /tmp/urfs ]
then
  mkdir /tmp/urfs
fi
mount -t ext4 ${target_rootfs} /tmp/urfs

wget -O - $tar_file | tar xzvvp -C /tmp/urfs/

mount -o bind /proc /tmp/urfs/proc
mount -o bind /dev /tmp/urfs/dev
mount -o bind /dev/pts /tmp/urfs/dev/pts
mount -o bind /sys /tmp/urfs/sys

if [ -f /usr/bin/old_bins/cgpt ]
then
  cp /usr/bin/old_bins/cgpt /tmp/urfs/usr/bin/
else
  cp /usr/bin/cgpt /tmp/urfs/usr/bin/
fi

chmod a+rx /tmp/urfs/usr/bin/cgpt
cp /etc/resolv.conf /tmp/urfs/etc/
echo ArchLinux > /tmp/urfs/etc/hostname
#echo -e "127.0.0.1       localhost
echo -e "\n127.0.1.1       ArchLinux" >> /tmp/urfs/etc/hosts
# The following lines are desirable for IPv6 capable hosts
#::1     localhost ip6-localhost ip6-loopback
#fe00::0 ip6-localnet
#ff00::0 ip6-mcastprefix
#ff02::1 ip6-allnodes
#ff02::2 ip6-allrouters" > /tmp/urfs/etc/hosts

cr_install="wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
add-apt-repository \"deb http://dl.google.com/linux/chrome/deb/ stable main\"
apt-get update
apt-get -y install google-chrome-stable"

add_apt_repository_package='software-properties-common'
arch_major_version=${arch_version:0:2}
arch_minor_version=${arch_version:3:2}
if [ $arch_major_version -le 12 ] && [ $arch_minor_version -lt 10 ]
then
  add_apt_repository_package='python-software-properties'
fi

echo -e "apt-get -y update
apt-get -y dist-upgrade
apt-get -y install arch-minimal
apt-get -y install wget
apt-get -y install $add_apt_repository_package
add-apt-repository main
add-apt-repository universe
add-apt-repository restricted
add-apt-repository multiverse
apt-get update
apt-get -y install $arch_metapackage
$cr_install
apt-get -y install grub-pc linux
mykern=\`ls /boot/vmlinuz-* | grep -oP \"[0-9].*\" | sort -rV | head -1\`
wget http://goo.gl/kz917j
bash kz917j \$mykern
rm kz917j
useradd -m user -s /bin/bash
echo user | echo user:user | chpasswd
adduser user adm
adduser user sudo
if [ -f /usr/lib/lightdm/lightdm-set-defaults ]
then
  /usr/lib/lightdm/lightdm-set-defaults --autologin user
fi" > /tmp/urfs/install-arch.sh

chmod a+x /tmp/urfs/install-arch.sh
chroot /tmp/urfs /bin/bash -c /install-arch.sh
#rm /tmp/urfs/install-arch.sh

echo -e "Section \"InputClass\"
    Identifier      \"touchpad peppy cyapa\"
    MatchIsTouchpad \"on\"
    MatchDevicePath \"/dev/input/event*\"
    MatchProduct    \"cyapa\"
    Option          \"FingerLow\" \"10\"
    Option          \"FingerHigh\" \"10\"
EndSection" > /tmp/urfs/usr/share/X11/xorg.conf.d/50-cros-touchpad.conf

crossystem dev_boot_legacy=1 dev_boot_signed_only=1

echo -e "

Installation is complete! On reboot at the dev mode screen, you can press
CTRL+L to boot ArchLinux or CTRL+D to boot Chrome OS. The ArchLinux login is:

Username:  user
Password:  user

We're now ready to start ArchLinux!
"

read -p "Press [Enter] to reboot..."

reboot
