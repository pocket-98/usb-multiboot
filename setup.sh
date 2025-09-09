#!/bin/bash

########################################
# set params
########################################
device=/dev/sda
efi_size=256M
iso_size=24G
iso_param_file=iso.txt

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
        if [ -f iso/tinycore/tinycore*iso ]; then
            tinycore_iso=$(ls iso/tinycore | grep -E "tinycore.*\.iso" | head -n 1)
            echo "found tinycore: '${tinycore_iso}'"
            echo "extracting vmlinuz and core.gz from iso"
            tiny=$(mktemp -d tiny-XXXXX)
            sudo mount -o ro,loop "iso/tinycore/${tinycore_iso}" "${tiny}"
            mkdir -p bin
            cp "${tiny}/boot/corepure64.gz" bin/corepure64.gz
            cp "${tiny}/boot/vmlinuz64" bin/vmlinuz64
            chmod 664 bin/corepure64.gz
            chmod 664 bin/vmlinuz64
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
        if [ -f iso/tinycore/${pkg}*tcz ]; then
            tcz=$(ls iso/tinycore/ | grep -E "${pkg}.*\.tcz" | head -n 1)
            echo "found tinycore ${pkg}: '${tcz}'"
            echo "extracting binaries from squash tcz"
            tiny=$(mktemp -d tiny-XXXXX)
            sudo mount -o ro,loop "iso/tinycore/${tcz}" "${tiny}"
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
    sudo cp bin/vmlinuz64 "${mnt}/boot/vmlinuz64"
    sudo cp bin/corepure64.gz "${mnt}/boot/corepure64.gz"
    sync

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

    # setup tinycore syslinux
    echo "installing tinycore syslinux"
    sudo tar -zxf bin/tc-syslinux.tar.gz -C "${mnt}"
    sync

    # setup tinycore tcinstall
    echo "installing tinycore tcinstall"
    sudo tar -zxf bin/tc-tcinstall.tar.gz -C "${mnt}"
    sync

    # add extra arch grub sources
    #echo "installing additional grub target source modules"
    #sudo tar --zstd -xf iso/grub*pkg.tar.zst -C "${mnt}" usr/lib/grub
    #sync

    # unmount
    echo "finished tinycore preparation"
    sudo umount "${mnt}/boot"
    sudo umount "${mnt}"
    rmdir "${mnt}"
}

_append_menu_entry() {
    cat << EOF | sudo tee -a "${5}/usr/local/etc/grub.d/40_custom"
menuentry 'tiny core from initram on ${device}${_part_efi}' {
	insmod part_msdos
	insmod ext2
	search --no-floppy --fs-uuid --set=root ${1}
	linux ${3}
	initrd ${4}
}

menuentry 'archlinux from usb partition ${device}${_part_linux}' {
	load_video
	set gfxpayload=keep
	insmod gzio
	insmod part_msdos
	insmod ext2
	search --no-floppy --fs-uuid --set=root ${2}
	linux /boot/vmlinuz-linux root=UUID=${2} rw quiet
	initrd /boot/initramfs-linux.img
}

EOF
}

_append_iso_entry() {
    cat << EOF | sudo tee -a "${1}/usr/local/etc/grub.d/40_custom"
menuentry '${3} (grub.cfg)' {
	search --no-floppy --fs-uuid --set=root ${2}
	set iso_path="${3}"
	set iso_uuid="${2}"
	insmod loopback
	loopback loop /\$iso_path
	set root=(loop)
	if [ -f (loop)/boot/grub/grub.cfg ]; then
		configfile (loop)/boot/grub/grub.cfg
	else
		if [ -f (loop)/boot/grub/loopback.cfg ]; then
			configfile (loop)/boot/grub/loopback.cfg
		else
			echo "error: couldnt find grub.cfg"
		fi
	fi
	loopback --delete loop
}
menuentry '${3} (efi)' {
	search --no-floppy --fs-uuid --set=root ${2}
	set iso_path="${3}"
	set iso_uuid="${2}"
	load_video
	insmod loopback
	loopback loop /\$iso_path
	linux (loop)${4} ${6}
	initrd (loop)${5}
}
EOF
}

_append_reboot_entry() {
    cat << EOF | sudo tee -a "${1}/usr/local/etc/grub.d/40_custom"
menuentry 'Reboot' --class restart {
	reboot
}
menuentry 'Shutdown' --class shutdown {
	halt
}
EOF
}

set_grub_menus() {
    # insert custom menu entries
    mnt=$(mktemp -d mnt-XXXXX)
    sudo mount "${device}${_part_linux}" "${mnt}"
    sudo mount "${device}${_part_iso}" "${mnt}/mnt"

    echo "setting grub menu entries"
    efi_uuid=$(sudo blkid "${device}${_part_efi}" | grep -Eo "\bUUID=\"[a-zA-Z0-9-]+\"" | cut -d'"' -f2)
    iso_uuid=$(sudo blkid "${device}${_part_iso}" | grep -Eo "\bUUID=\"[a-zA-Z0-9-]+\"" | cut -d'"' -f2)
    linux_uuid=$(sudo blkid "${device}${_part_linux}" | grep -Eo "\bUUID=\"[a-zA-Z0-9-]+\"" | cut -d'"' -f2)
    _append_menu_entry "${efi_uuid}" "${linux_uuid}" /vmlinuz64 /corepure64.gz "${mnt}"
    cat "${iso_param_file}" | while read iso_line; do
        iso=$(echo -e "${iso_line}" | awk '{print $1}')
        kernel=$(echo -e "${iso_line}" | awk '{print $2}')
        initram=$(echo -e "${iso_line}" | awk '{print $3}')
        flags=$(echo -e "${iso_line}" | awk '{s=""; for(i=4; i<=NF; i++) s=s $i " "; print s }')
	if [ -f "iso/${iso}" ]; then
            echo "copying '${iso}' to ${device}${_part_iso}"
            sudo cp "iso/${iso}" "${mnt}/mnt/"
            _append_iso_entry "${mnt}" "${iso_uuid}" "${iso}" "${kernel}" "${initram}" "${flags}"
            sync
        else
            echo "skipping '${iso}' since not downloaded"
        fi
    done
    _append_reboot_entry

    sudo umount "${mnt}/mnt"
    sudo umount "${mnt}"
    echo "finished copying iso and setting grub boot menus"
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
    sudo chroot "${mnt}" cp /usr/local/share/syslinux/memdisk /boot/grub/memdisk
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
    sudo cp bin/newcore.gz "${mnt}/boot/corepure64.gz"
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
    get_tiny_pkg syslinux
    get_tiny_pkg tcinstall
    #get_arch_grub

    install_tinycore
    set_grub_menus
    install_grub
    repack_cpio
}

main

