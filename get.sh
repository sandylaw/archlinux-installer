#!/bin/bash
while true; do
	wget https://raw.githubusercontent.com/sandylaw/archlinux-installer/master/install.sh
	wget https://raw.githubusercontent.com/sandylaw/archlinux-installer/master/setup.sh
	wget https://raw.githubusercontent.com/sandylaw/archlinux-installer/master/removecrypt.sh
	if [[ -e install.sh ]] && [[ -e setup.sh ]] && [[ -e removecrypt.sh ]]; then
		break
	fi
done
