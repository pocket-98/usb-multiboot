#!/bin/bash

########################################
# set params
########################################
downloads=(
    "tinycore"
    "coreutils_tc"
    "grub_tc"
    "efiboot_tc"
    "liblzma_tc"
    "liblvm_tc"
    "libudev_tc"
    #"grub_arch"
    "proxmox"
    "arch"
)

########################################
# script internal variables
########################################
tinycore_url="http://tinycorelinux.net/16.x/x86_64/release/TinyCorePure64-16.1.iso"
tinycore_file="tinycore64-16.1.iso"
tinycore_sha="0b995a561365057ff17a9983a08a52d8f0c81153fc6eba1a4e863be03bac2254"

coreutils_tc_url="http://tinycorelinux.net/16.x/x86_64/tcz/coreutils.tcz"
coreutils_tc_file="coreutils-9.5.tcz"
coreutils_tc_sha="2377c14d86b0f35458e96b6339cca1daeed1854f53c797b17b7afd71ba7bee6c"

grub_tc_url="http://tinycorelinux.net/16.x/x86_64/tcz/grub2-multi.tcz"
grub_tc_file="grub2-2.12.tcz"
grub_tc_sha="e21e9b4d54171ac79eed5583925ad9c385064e27ace7badb1773ca180b714678"

efiboot_tc_url="http://tinycorelinux.net/16.x/x86_64/tcz/efibootmgr.tcz"
efiboot_tc_file="efibootmgr-18.tcz"
efiboot_tc_sha="f8844b7d2728ee02a47e0a1795d61bfe4703c13509a030dcbcb009c50c4d0fe3"

liblzma_tc_url="http://tinycorelinux.net/16.x/x86_64/tcz/liblzma.tcz"
liblzma_tc_file="liblzma-5.6.3.tcz"
liblzma_tc_sha="b550c00b318a89885f2a9d4f7d6a15b8d0834e50aab9094d50d417dba66828e7"

liblvm_tc_url="http://tinycorelinux.net/16.x/x86_64/tcz/liblvm2.tcz"
liblvm_tc_file="liblvm2-2.02.177.tcz"
liblvm_tc_sha="4df728b069c986256f4c6e8c64ba1933822ffb9ddac0b2659472f4f34a829ed1"

libudev_tc_url="http://tinycorelinux.net/16.x/x86_64/tcz/udev-lib.tcz"
libudev_tc_file="libudev-173.tcz"
libudev_tc_sha="6b357512151a3dae7f71623d1efcd228f0460595bcbd88dbf914c18f112b7087"

#grub_arch_url="https://mirror.rackspace.com/archlinux/core/os/x86_64/grub-2:2.12.r359.g19c698d12-1-x86_64.pkg.tar.zst"
#grub_arch_file="grub2-2.12.pkg.tar.zst"
#grub_arch_sha="c31c9aca8e34f4ad99f8319a032ce39b9e8dabaeeb78b4b299618c7ae5f771f8"

proxmox_url="https://enterprise.proxmox.com/iso/proxmox-ve_9.0-1.iso"
proxmox_file="proxmox-ve_9.0-1.iso"
proxmox_sha="228f948ae696f2448460443f4b619157cab78ee69802acc0d06761ebd4f51c3e"

arch_url="https://mirror.rackspace.com/archlinux/iso/2025.09.01/archlinux-2025.09.01-x86_64.iso"
arch_file="archlinux-2025.09.01-x86_64.iso"
arch_sha="961002fab836819b599e770aa25ff02bff1697d1d051140062066a5ff47d6712"


########################################
# download and/or verify download
########################################
download_and_verify() {
    dl=$1
    iso_url="${dl}_url"
    iso_url="${!iso_url}"
    iso_file="${dl}_file"
    iso_file="${!iso_file}"
    iso_sha="${dl}_sha"
    iso_sha="${!iso_sha}"
    need_to_download=true
    echo -n "${dl}: '${iso_file}': "
    if [ -f "${iso_file}" ]; then
        sha256sum "${iso_file}" | grep "${iso_sha}" > /dev/null
        iso_sha_match=$?
        if [ "${iso_sha_match}" -eq 0 ]; then
            msg="downloaded and verified sha256 hash"
            need_to_download=false
        else
            msg="sha256 hash mismatch: redownloading"
        fi
    else
        msg="downloading"
    fi
    echo "${msg}"

    if "${need_to_download}"; then
        curl -o "${iso_file}" -Lk "${iso_url}"
        sha256sum "${iso_file}" | grep "${iso_sha}" > /dev/null
        iso_sha_match=$?
        if [ "${iso_sha_match}" -eq 0 ]; then
            echo "downloaded and verified sha256 hash"
        else
            echo "error: sha256 hash mismatch on download, deleting bad iso"
            rm "${iso_file}"
        fi
    fi
}

main() {
    for dl in "${downloads[@]}"; do
        download_and_verify "${dl}"
    done
}

main

