#!/bin/bash
function pause() {
	echo "Warning: Will delete data: luks_lvm!!!"
	read -r -s -n 1 -p "Press any key to continue . . ."
	echo ""
}
pause
umount -R /mnt
swapoff -a
lvremove -ff arch || true
vgremove -ff arch || true
pvremove --force --force /dev/mapper/luks_lvm || true
pvs
cryptsetup luksClose luks_lvm
cryptsetup-reencrypt --decrypt data_p
cp removecrypt.sh.bak removecrypt.sh
