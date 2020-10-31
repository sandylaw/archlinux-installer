#!/bin/bash
#v2020.10.31 modify by sandylaw <freelxs@gmail.com>
log_file=install.log
exec > >(tee -a ${log_file} )
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
echo "First, Please Setting up disk partitions, eif/boot/data three partition at least"
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
read -rp "Please enter your efi partition: " efi_p
read -rp "Please enter your boot partition: " boot_p
read -rp "Will you use crypt encrypt the root partition?[default:yes]: " crypt
crypt=${crypt:-yes}
case "$crypt" in
yes | y | Y | YES)
	modprobe dm-crypt || exit
	modprobe dm-mod || exit
	read -rp "Please enter your data(root,home.var...) partition: " data_p

	rbsize=$(lsblk -b | grep "${data_p##/dev/}" | awk '{print $4}')
	rsize=$(echo "scale=2;$rbsize/1073741824" | bc)
	root_size=$(echo "scale=1;$rsize/5" | bc)
	var_size=$(echo "scale=1;$rsize/5" | bc)
	usr_size=$(echo "scale=1;$rsize/5" | bc)
	opt_size=$(echo "scale=1;$rsize/8" | bc)
	tmp_size=$(echo "scale=1;$rsize/8" | bc)
        swap_size=$(echo "scale=1;$rsize/8" | bc)
	
	if [[ "$(echo "$root_size > 100 " | bc)" == 1 ]]; then
		root_size=100
	fi
	if [[ "$(echo "$swap_size > 16 " | bc)" == 1 ]]; then
		swap_size=16
	fi
	if [[ "$(echo "$var_size > 200 " | bc)" == 1 ]]; then
		var_size=200
	fi
	if [[ "$(echo "$tmp_size > 50 " | bc)" == 1 ]]; then
		tmp_size=50
	fi
	if [[ "$(echo "$usr_size > 200 " | bc)" == 1 ]]; then
		usr_size=200
	fi
	if [[ "$(echo "$opt_size > 100 " | bc)" == 1 ]]; then
		opt_size=100
	fi
	home_size="$(echo "scale=1;$rsize-$root_size-$var_size-$usr_size-$opt_size-$tmp_size-$swap_size" | bc)"
        echo "********************************************"
	echo "********************************************"
	echo "********************************************"
	echo "         Please input YES, not yes          "
	echo "         And then input passphrase          "
	echo "********************************************"
	cryptsetup -v -y -s 512 -h sha512 luksFormat "$data_p" || exit
        cp removecrypt.sh removecrypt.sh.bak
        sed -ri "s:data_p:$data_p:1" removecrypt.sh || exit
	cryptsetup open "$data_p" luks_lvm || exit
	pvcreate /dev/mapper/luks_lvm || exit
	vgcreate -ff arch /dev/mapper/luks_lvm || exit
	lvcreate -n root -L "${root_size}"G arch || exit
	lvcreate -n var -L "${var_size}"G arch || exit
	lvcreate -n usr -L "${usr_size}"G arch || exit
	lvcreate -n opt -L "${opt_size}"G arch || exit
	lvcreate -n home -L "${home_size}"G arch || exit
	lvcreate -n tmp -L "${tmp_size}"G arch || exit
	lvcreate -n swap -L "${swap_size}" arch || exit
	mkfs.btrfs -L root /dev/mapper/arch-root || exit
	mkfs.btrfs -L var /dev/mapper/arch-var || exit
	mkfs.btrfs -L usr /dev/mapper/arch-usr || exit
	mkfs.btrfs -L opt /dev/mapper/arch-opt || exit
	mkfs.btrfs -L home /dev/mapper/arch-home || exit
	mkfs.btrfs -L tmp /dev/mapper/arch-tmp || exit
	mkswap /dev/mapper/arch-swap || exit
	swapon /dev/mapper/arch-swap || exit
	swapon -a
	swapon -s
	mount /dev/mapper/arch-root /mnt || exit
	mkdir -p /mnt/{home,boot,var,usr,opt,tmp} || exit
	mount /dev/mapper/arch-var /mnt/var || exit
	mount /dev/mapper/arch-usr /mnt/usr || exit
	mount /dev/mapper/arch-opt /mnt/opt || exit
	mount /dev/mapper/arch-home /mnt/home || exit
	mount /dev/mapper/arch-tmp /mnt/tmp || exit
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

# Creating filesystem
mkfs.fat -F32 "$efi_p" || exit
mkfs.ext4 "$boot_p" || exit
lsblk -f
df -Th

# Selecting Mirror
pacman -S --noconfirm reflector
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
reflector -c "US" -f 12 -l 10 -n 12 --save /etc/pacman.d/mirrorlist

# Installing Arch Linux
mkdir -p /mnt/boot || exit
mount "$boot_p" /mnt/boot || exit
mkdir -p /mnt/boot/efi || exit
mount "$efi_p" /mnt/boot/efi || exit

pacstrap /mnt base base-devel linux linux-firmware --noconfirm

data_uid=$(blkid | grep "$data_p" | awk '{print $2}')

grub_default_arg="quiet cryptdevice=$data_uid:luks_lvm resume=/dev/mapper/arch-swap"

# Configuring install
genfstab -U -p /mnt >>/mnt/etc/fstab
mv setup.sh /mnt
cp install.log /mnt/var/log/install.log
if test "$layout" = "" && [[ -n "$data_p" ]]; then
	arch-chroot /mnt /bin/bash setup.sh "$efi_p" us "$data_p" "$grub_default_arg"
elif test "$layout" = "" && [[ -z "$data_p" ]]; then
	arch-chroot /mnt /bin/bash setup.sh "$efi_p" us
else
	arch-chroot /mnt /bin/bash setup.sh "$efi_p" "$layout"
fi
sync
sync
echo "Will Reboot"
pause
exit
#umount -R /mnt
#swapoff -a
#shutdown -r now
