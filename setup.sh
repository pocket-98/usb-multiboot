#!/bin/bash

########################################
# set params
########################################
device=/dev/sda
efi_size=256M
iso_size=24G

########################################
# set script standard variables
########################################
_part_efi=1
_part_iso=2
_part_linux=3

########################################
# set usb partitions
########################################
set_partitions() {
    echo "clearing all partitions from ${device}"
    sudo wipefs --all "${device}"
    echo "setting new partition table for ${device}"
    cat << EOF | sudo fdisk --wipe=always "${device}"
o
n
p
1

+${efi_size}
t
ef
a
n
p
2

+${iso_size}
t
2
b
n
p
3


t
3
83
w

EOF

    sleep 2
    echo "formatting efi partition"
    sudo mkfs.vfat -F32 -n EFI "${device}${_part_efi}"
    sleep 2
    echo "formatting iso partition"
    sudo mkfs.vfat -F32 -n ISO "${device}${_part_iso}"
    sleep 2
    echo "formatting linux partition"
    sudo mkfs.ext4 -F -L linux "${device}${_part_linux}"
}

########################################
# get tinycore core.gz
########################################
get_tinycore() {
    if [ -f bin/core.gz ] && [ -f bin/vmlinuz ]; then
        echo "found tinycore kernel and initram 'vmlinuz' and 'core.gz'"
    else
        if [ -f iso/tinycore*iso ]; then
            tinycore_iso=$(ls iso/ | grep -E "tinycore.*\.iso" | head -n 1)
            echo "found tinycore: '${tinycore_iso}'"
            echo "extracting vmlinuz and core.gz from iso"
            tiny=$(mktemp -d tiny-XXXXX)
            sudo mount -o ro,loop "iso/${tinycore_iso}" "${tiny}"
            mkdir -p bin
            cp "${tiny}/boot/corepure64.gz" bin/core.gz
            cp "${tiny}/boot/vmlinuz64" bin/vmlinuz
            chmod 664 bin/core.gz
            chmod 664 bin/vmlinuz
            sudo umount "${tiny}"
            rmdir "${tiny}"
        else
            echo "error: couldn't find tinycore iso, please download it"
            echo "get it by navigating into ./iso/ and running ./download.sh"
            exit 1
        fi
    fi
}

get_tiny_pkg() {
    pkg="${1}"
    if [ -f bin/tc-${pkg}.tar.gz ]; then
        echo "found ${pkg} tinycore binaries"
    else
        if [ -f iso/${pkg}*tcz ]; then
            tcz=$(ls iso/ | grep -E "${pkg}.*\.tcz" | head -n 1)
            echo "found tinycore ${pkg}: '${tcz}'"
            echo "extracting binaries from squash tcz"
            tiny=$(mktemp -d tiny-XXXXX)
            sudo mount -o ro,loop "iso/${tcz}" "${tiny}"
            mkdir -p bin
            tar -zcf "bin/tc-${pkg}.tar.gz" -C "${tiny}/" .
            sudo umount "${tiny}"
            rmdir "${tiny}"
        else
            echo "error: couldn't find tinycore ${pkg} binaries, please download it"
            echo "get it by navigating into ./iso/ and running ./download.sh"
            exit 1
        fi
    fi
}

########################################
# get tinycore grub2 source
########################################
get_arch_grub() {
    if [ -f iso/grub2*pkg.tar.zst ]; then
        echo "found grub2 archlinux binaries"
    else
        echo "error: couldn't find archlinux grub2 binaries, please download it"
        echo "get it by navigating into ./iso/ and running ./download.sh"
        exit 1
    fi
}

########################################
# install grub
########################################
append_menu_entry() {
    cat << EOF | sudo tee -a "${5}/usr/local/etc/grub.d/40_custom"
menuentry 'tiny core on ${device}${_part_linux}' {
	insmod part_msdos
	insmod ext2
	search --no-floppy --fs-uuid --set=root ${1}
	linux ${3} root=UUID=${2} rw loglevel=3 quiet
	initrd ${4}
}

menu
EOF
}

install_tinycore() {
    mnt=$(mktemp -d mnt-XXXXX)
    sudo mount "${device}${_part_linux}" "${mnt}"
    sudo mkdir -p "${mnt}/boot"
    sudo mount "${device}${_part_efi}" "${mnt}/boot"
    echo "mounting partitions"

    # setup tinycore
    echo "installing tinycore linux"
    cd "${mnt}"
    gzip -cd ../bin/core.gz | sudo cpio -idm > /dev/null
    cd ..
    sudo cp bin/vmlinuz "${mnt}/boot/vmlinuz"
    sudo cp bin/core.gz "${mnt}/boot/initramfs.gz"
    sync

    # setup fstab
    echo "setting efi boot partition in /etc/fstab"
    efi_uuid=$(sudo blkid "${device}${_part_efi}" | grep -Eo "\bUUID=\"[a-zA-Z0-9-]+\"" | cut -d'"' -f2)
    echo "UUID=${efi_uuid}  /boot  vfat  umask=0077  0 1" | sudo tee -a "${mnt}/etc/fstab"

    # setup tinycore coreutils
    echo "installing tinycore coreutils"
    sudo tar -zxf bin/tc-coreutils.tar.gz -C "${mnt}" ./usr/local/bin/stat
    sync

    # setup tinycore grub
    echo "installing tinycore grub2"
    sudo tar -zxf bin/tc-grub2.tar.gz -C "${mnt}"
    sync

    # setup tinycore efibootmgr
    echo "installing tinycore efibootmgr"
    sudo tar -zxf bin/tc-efibootmgr.tar.gz -C "${mnt}"
    sync

    # setup tinycore liblzma
    echo "installing tinycore liblzma"
    sudo tar -zxf bin/tc-liblzma.tar.gz -C "${mnt}"
    sync

    # setup tinycore liblvm
    echo "installing tinycore liblvm"
    sudo tar -zxf bin/tc-liblvm.tar.gz -C "${mnt}"
    sync

    # setup tinycore libudev
    echo "installing tinycore libudev"
    sudo tar -zxf bin/tc-libudev.tar.gz -C "${mnt}"
    sync

    # add extra arch grub sources
    #echo "installing additional grub target source modules"
    #sudo tar --zstd -xf iso/grub*pkg.tar.zst -C "${mnt}" usr/lib/grub
    #sync

    # insert custom menu entries
    echo "setting grub menu entry"
    linux_uuid=$(sudo blkid "${device}${_part_linux}" | grep -Eo "\bUUID=\"[a-zA-Z0-9-]+\"" | cut -d'"' -f2)
    append_menu_entry "${efi_uuid}" "${linux_uuid}" /vmlinuz /initramfs.gz "${mnt}"
    sync

    # unmount
    echo "finished tinycore preparation"
    sudo umount "${mnt}/boot"
    sudo umount "${mnt}"
    rmdir "${mnt}"
}
    
install_grub() {
    mnt=$(mktemp -d mnt-XXXXX)
    sudo mount "${device}${_part_linux}" "${mnt}"
    sudo mount "${device}${_part_efi}" "${mnt}/boot"

    # mount /proc /dev /sys
    echo "preparing mounts for chroot"
    sudo mkdir -p "${mnt}/proc"
    sudo mkdir -p "${mnt}/dev"
    sudo mkdir -p "${mnt}/sys"
    sudo mount --rbind /proc "${mnt}/proc"
    sudo mount --make-rslave "${mnt}/proc"
    sudo mount --rbind /dev "${mnt}/dev"
    sudo mount --make-rslave "${mnt}/dev"
    sudo mount --rbind /sys "${mnt}/sys"
    sudo mount --make-rslave "${mnt}/sys"

    echo "running grub-install in tinycore chroot"
    sudo chroot "${mnt}" mkdir /usr/local/share/locale
    sudo LD_LIBRARY_PATH=/usr/local/lib chroot "${mnt}" /usr/local/sbin/grub-install --boot-directory=/boot --directory=/usr/local/lib/grub/x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable "${device}"
    sudo LD_LIBRARY_PATH=/usr/local/lib chroot "${mnt}" /usr/local/sbin/grub-install --boot-directory=/boot --directory=/usr/local/lib/grub/i386-pc "${device}"
    sudo LD_LIBRARY_PATH=/usr/local/lib chroot "${mnt}" /usr/local/sbin/grub-mkconfig -o /boot/grub/grub.cfg
    sync

    sudo umount -R "${mnt}/proc"
    sudo umount -R "${mnt}/dev"
    sudo umount -R "${mnt}/sys"

    sudo umount "${mnt}/boot"
    sudo umount "${mnt}"
    
    echo "finished grub install"
    rmdir "${mnt}"
}

########################################
# repack initramfs cpio
########################################
repack_cpio() {
    mnt=$(mktemp -d mnt-XXXXX)
    echo "repacking initramfs cpio"
    sudo mount "${device}${_part_linux}" "${mnt}"

    sudo chroot "${mnt}" sh -c "find / | sudo cpio -o -H newc" | gzip > bin/newcore.gz
    sync
    sudo mount "${device}${_part_efi}" "${mnt}/boot"
    sudo cp bin/newcore.gz "${mnt}/boot/initramfs.gz"
    sync

    sudo umount "${mnt}/boot"
    sudo umount "${mnt}"
    echo "updated boot initram"
    rmdir "${mnt}"
}

########################################
# main
########################################

main() {
    set_partitions

    get_tinycore
    get_tiny_pkg coreutils
    get_tiny_pkg grub2
    get_tiny_pkg efibootmgr
    get_tiny_pkg liblzma
    get_tiny_pkg liblvm
    get_tiny_pkg libudev
    #get_arch_grub

    install_tinycore
    install_grub
    repack_cpio
}

main

