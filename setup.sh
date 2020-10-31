#!/bin/bash
#v2020.10.31 modify by sandylaw <freelxs@gmail.com>
# $0 refers to this script itself
# $1 refers to the first argument passed (in our case, from install.sh it is $EFI)
# $2 refers to the second argument passed (in our case, from install.sh it is $layout)
# $3 refers to encry data partition  (in our case, from install.sh it is $data_p)
# $4 refers to grub args, 
log_file=/var/log/install.log
exec > >(tee -a ${log_file} )
exec 2> >(tee -a ${log_file} >&2)

echo "Arch-chroots"
data_p="${3:-none}"
grub_default_arg="${4:-none}"
user=user
userpasswd=user
clear
echo "Setting up ArchLinux..."
pacman -Syy

# Setting Locale
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#zh_CN.GB18030/zh_CN.GB18030/' /etc/locale.gen
sed -i 's/^#zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >/etc/locale.conf
export LANG=en_US.UTF-8

echo "KEYMAP=$2" >>/etc/vconsole.conf

# Network Configuration
echo arch >/etc/hostname
touch /etc/hosts
{
	echo "127.0.0.1    localhost"
	echo "::1          localhost"
	echo "127.0.1.1    arch"
} >>/etc/hosts

# User Accounts
clear
echo "Setting up root user..."
echo root:passwd | chpasswd

# Adds a new user to wheel group

useradd -m -G wheel "$user"


echo "$user":"$userpasswd" | chpasswd
pacman -S --noconfirm sudo # Installs sudo

# Config sudo
# allow users of group wheel to use sudo
sed -i 's/^# %wheel ALL=(ALL) ALL$/%wheel ALL=(ALL) ALL/' /etc/sudoers

# Install intel-ucode for Intel CPU
is_intel_cpu=$(lscpu | grep 'Intel' &>/dev/null && echo 'yes' || echo '')
if [[ -n "$is_intel_cpu" ]]; then
	pacman -S --noconfirm intel-ucode --overwrite=/boot/intel-ucode.img
fi

# Desktop environment setup
pacman -S --noconfirm xorg xorg-server
# graphics driver
nvidia=$(lspci | grep -e VGA -e 3D | grep 'NVIDIA' 2>/dev/null || echo '')
amd=$(lspci | grep -e VGA -e 3D | grep 'AMD' 2>/dev/null || echo '')
intel=$(lspci | grep -e VGA -e 3D | grep 'Intel' 2>/dev/null || echo '')
if [[ -n "$nvidia" ]]; then
	pacman -S --noconfirm nvidia
fi

if [[ -n "$amd" ]]; then
	pacman -S --noconfirm xf86-video-amdgpu
fi

if [[ -n "$intel" ]]; then
	pacman -S --noconfirm xf86-video-intel
fi

if [[ -n "$nvidia" && -n "$intel" ]]; then
	pacman -S --noconfirm bumblebee
	gpasswd -a "$user" bumblebee
	systemctl enable bumblebeed
fi

# Network Manager
echo "Install network packages"
pacman -S --noconfirm networkmanager netctl wpa_supplicant dhclient dialog
systemctl enable NetworkManager.service # Would enable network manager in startup

# Xfce
echo "Install xfce4"
pacman -S --noconfirm xfce4 mousepad lightdm lightdm-gtk-greeter openssh
systemctl enable lightdm.service
systemctl enable sshd.service
# Finishing up
echo "The Setup will install Sofe soft,Eg:Firefox, Python3, Geany, GCC, Make and Terminal by default"
pacman -S --noconfirm keepassxc firefox python3 python3-pip gcc make
# compression/decompression tools
pacman -S --noconfirm unrar p7zip

# useful shell utils
pacman -S --noconfirm bash-completion vim bind-tools dos2unix rsync wget git tree
pacman -S --noconfirm net-tools whois screen inotify-tools perl-rename recode
pacman -S --noconfirm openbsd-netcat

# Use vim instead vi
ln -s /usr/bin/vim /usr/local/bin/vi

# Add archlinuxcn repository
echo ""
echo "Set archlinuxcn "
if ! grep 'archlinuxcn' /etc/pacman.conf &>/dev/null; then

	tee /etc/pacman.d/archlinuxcn-mirrorlist <<EOF
Server = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch
Server = http://mirrors.cqu.edu.cn/archlinux-cn/\$arch
Server = http://repo.archlinuxcn.org/\$arch
EOF

	tee -a /etc/pacman.conf <<EOF
[archlinuxcn]
SigLevel = Optional TrustedOnly
Include = /etc/pacman.d/archlinuxcn-mirrorlist
EOF
fi
pacman -Syy
pacman -S --noconfirm archlinuxcn-keyring archlinuxcn-mirrorlist-git

# Install AUR helper from archlinuxcn repo
pacman -S --noconfirm yay

# Fonts Sounds
echo ""
echo "Install fonts"
pacman -S --noconfirm ttf-dejavu wqy-microhei noto-fonts-cjk
echo "Installing alsa and pulseaudio"
pacman -S --noconfirm \
	pulseaudio-{equalizer,alsa} \
	alsa-{utils,plugins,firmware}
# Set encrypt
if [[ -n "${3}" ]]; then
	sed -ri '/^HOOKS=/cHOOKS=\"base udev autodetect modconf block keyboard keymap encrypt lvm2 resume filesystems fsck\"' /etc/mkinitcpio.conf

fi

# Installing bootloader
pacman -S --noconfirm os-prober ntfs-3g grub btrfs-progs efibootmgr lvm2
os-prober
mkinitcpio -v -p linux
grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg
grub-mkconfig -o /boot/efi/EFI/arch/grub.cfg || true
if ! [[ "${data_p}" == "none" ]]; then
	sed -ri "/^GRUB_CMDLINE_LINUX_DEFAULT=/cGRUB_CMDLINE_LINUX_DEFAULT=\"${grub_default_arg}\"" /etc/default/grub
	dd if=/dev/urandom of=/crypto_keyfile.bin bs=512 count=10
	chmod 000 /crypto_keyfile.bin
	chmod 600 /boot/initramfs-linux*
	cryptsetup luksAddKey "$data_p" /crypto_keyfile.bin || exit
	sed -ri '/^FILES=/d' /etc/mkinitcpio.conf
	sed -ri '/^#[ ]*FILES/{n;n;s|$|\nFILES=\"/crypto_keyfile.bin\"|}' /etc/mkinitcpio.conf
	mkinitcpio -p linux
	grub-mkconfig -o /boot/grub/grub.cfg
	grub-mkconfig -o /boot/efi/EFI/arch/grub.cfg || true
fi

systemctl set-default graphical.target # Sets Graphical Target as default
rm -f "$0"
