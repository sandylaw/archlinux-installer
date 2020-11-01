#!/bin/bash
#v2020.10.31 modify by sandylaw <freelxs@gmail.com>
log_file=install.log
exec > >(tee -a ${log_file})
exec 2> >(tee -a ${log_file} >&2)

function pause() {
	read -r -s -n 1 -p "Press any key to continue . . ."
	echo ""
}
echo "        	 
                 ##
                ####
               ######
              ########
             ##########
            ############
           ##############
          ################
         ##################
        ####################
       ######################
      #########      #########
     ##########      ##########
    ###########      ###########
   ##########          ##########
  #######                  #######
 ####                          ####
###                              ###
                     "
echo "Install Arch Linux, written by Asif Rasheed"
echo "Install Arch Linux, modify by SandyLaw <freelxs@gmail.com>"
echo "First, Please Setting up disk partitions, eif/boot/root(data) three partition at least"
scriptDir=$(
	cd "$(dirname "$0")" || exit
	pwd
)
if [[ -d "/sys/firmware/efi/efivars" ]]; then
	loader=efi
else
	loader=bios
fi
lsblk -f
sleep 5
read -rp "Are you ready? yes or no: " ready_state
case "$ready_state" in
yes | y | Y | YES) ;;
*)
	exit
	;;
esac
read -rp "Please enter your keyboard layout (default: us): " layout

if test "$layout" = ""; then
	loadkeys us
else
	loadkeys "$layout"
fi
if [[ "$loader" == efi ]]; then
	while true; do
		read -rp "Please enter your efi partition: " efi_p
		if blkid "$efi_p"; then
			mkfs.fat -F32 -L efi "$efi_p" || exit
			break
		fi
	done
fi
while true; do
	read -rp "Please enter your boot partition: " boot_p
	if blkid "$boot_p" && blkid "$efi_p"; then
		mkfs.ext4 -L boot "$boot_p" || exit
	elif blkid "$boot_p" && ! blkid "$efi_p"; then
		if [[ $boot_p =~ nvme ]]; then
			disk=${boot_p:0:-2}
		else
			disk=$(echo "${boot_p}" | tr -cd 'a-z''A-Z''/')
		fi
		disk_type=$(fdisk -l "$disk" | tr '[:upper:]' '[:lowwer:]' | grep 'disklabel type' | awk -F ":" '{print $2}')
		boot_type=$(fdisk -l "$disk" | tr '[:upper:]' '[:lowwer:]' | grep "$boot_p" | awk -F '{print $6}')
		if [[ "$disk_type" == "gpt" ]] && ! [[ "$boot_type" == 'bios boot' ]]; then
			echo "Please use fdisk , change the $boot_p type to 'BIOS boot'"
			break
		fi
	else

		break
	fi
done

read -rp "Will you encrypt the root partition?[default:yes]: " crypt
crypt=${crypt:-yes}
case "$crypt" in
yes | y | Y | YES)
	modprobe dm-crypt || exit
	modprobe dm-mod || exit
	while true; do
		read -rp "Please enter your data(root,home.var...) partition: " data_p
		if blkid "$data_p"; then
			break
		fi
	done
	echo "********************************************"
	echo "********************************************"
	echo "********************************************"
	echo "         Please input YES, not yes          "
	echo "         And then input passphrase          "
	echo "********************************************"
	cryptsetup -y -v --cipher=aes-xts-plain64 --key-size 512 --hash=sha512 luksFormat "$data_p" || exit
	cp removecrypt.sh removecrypt.sh.bak
	sed -ri "s:data_p:$data_p:g" removecrypt.sh || exit
	cryptsetup luksOpen "$data_p" luks || exit
	mkfs.btrfs -L archlinux /dev/mapper/luks
	mount -o compress=zstd /dev/mapper/luks /mnt || exit
	cd /mnt || exit
	btrfs subvolume create @
	btrfs subvolume create @home
	btrfs subvolume create @var
	btrfs subvolume create @log
	btrfs subvolume create @srv
	btrfs subvolume create @pkg
	btrfs subvolume create @tmp
	cd "$scriptDir" || exit
	umount /mnt || exit
	mount -o compress=zstd,subvol=@ /dev/mapper/luks /mnt
	mkdir -p /mnt/{home,boot,var,var/{log,cache/pacman/pkg},srv,tmp} || exit
	mount -o compress=zstd,subvol=@home /dev/mapper/luks home
	mount -o compress=zstd,subvol=@var /dev/mapper/luks var
	mount -o compress=zstd,subvol=@log /dev/mapper/luks var/log
	mount -o compress=zstd,subvol=@pkg /dev/mapper/luks var/cache/pacman/pkg
	mount -o compress=zstd,subvol=@srv /dev/mapper/luks srv
	mount -o compress=zstd,subvol=@tmp /dev/mapper/luks tmp

	lsblk -f
	;;
*)
	lsblk -f
	while true; do
		read -rp "Please enter your root partition: " root_p
		if df | grep "$root_p"; then
			break
		fi
	done
	read -rp "Please enter your home partition: " home_p
	read -rp "Please enter your usr partition: " usr_p
	read -rp "Please enter your var partition: " var_p
	read -rp "Please enter your opt partition: " opt_p
	read -rp "Please enter your tmp partition: " tmp_p
	read -rp "Please enter your swap partition: " swap_p
	mkfs.ext4 -L root "$root_p" || exit
	mount "$root_p" /mnt || exit
	dirs=(home usr var opt tmp)
	y=0
	for x in $home_p $usr_p $var_p $opt_p $tmp_p; do
		if [[ -n $x ]]; then
			mkfs.ext4 "$x" || exit
			mkdir -p /mnt/"${dirs[$y]}" || exit
			mount "$x" /mnt/"${dirs[$y]}" || exit
		fi
		y=$((y + 1))
	done
	if [[ -n "$swap_p" ]]; then
		mkswap "$swap_p" || exit
		swapon "$swap_p" || exit
		swapon -a
		swapon -s
	fi
	;;
esac

# Display filesystem

lsblk -f
df -Th

# Selecting Mirror
pacman -S --noconfirm reflector
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
reflector -c "US" -f 12 -l 10 -n 12 --save /etc/pacman.d/mirrorlist

# Installing Arch Linux
mkdir -p /mnt/boot || exit
mount "$boot_p" /mnt/boot || exit
if [[ "$loader" == efi ]]; then
	mkdir -p /mnt/boot/efi || exit
	mount "$efi_p" /mnt/boot/efi || exit
fi
pacstrap /mnt base base-devel linux linux-firmware --noconfirm

data_uid=$(blkid | grep "$data_p" | awk '{print $2}')

grub_default_arg="quiet cryptdevice=$data_uid:luks"

# Configuring install
genfstab -U -p /mnt >>/mnt/etc/fstab
cp "$scriptDir"/setup.sh /mnt || pause
cp "$scriptDir"/install.log /mnt/var/log/install.log || pause
if test "$layout" = "" && [[ -n "$data_p" ]]; then
	arch-chroot /mnt /bin/bash setup.sh "$efi_p" us "$data_p" "$grub_default_arg" "$loader"
elif test "$layout" = "" && [[ -z "$data_p" ]]; then
	arch-chroot /mnt /bin/bash setup.sh "$efi_p" us
else
	arch-chroot /mnt /bin/bash setup.sh "$efi_p" "$layout"
fi
sync
sync
echo "Please Reboot"
pause
rm /mnt/setup.sh
exit
#umount -R /mnt
#swapoff -a
#shutdown -r now
