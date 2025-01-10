#!/bin/bash

if [ -f ~/.rise.config ]; then
	echo "This script has already been executed";
	exit 1;
fi

if [ -f ~/running_x11.txt ]; then
	echo "File exists."
	mv ~/.rise.config1 ~/.rise.config
	sudo wget -O /usr/share/rpd-wallpaper/fisherman.jpg https://www.dupage88.net/site/public/agoraimages/?item=18485
	
	echo "@unclutter -idle 0" | sudo tee -a /etc/xdg/lxsession/LXDE-pi/autostart
	
	cd ~
	wget https://storage.googleapis.com/install-versions.risevision.com/installer-lnx-arm64.sh
	chmod +x installer-lnx-arm64.sh
	./installer-lnx-arm64.sh --accept

else
 
	if [ -f ~/aptupgrade.txt ]; then
	echo "File exists."
		sudo raspi-config nonint do_wayland W1
  		sudo raspi-config nonint do_blanking 1
		touch ~/running_x11.txt
		sudo reboot
	else
		echo "File does not exist."
		echo "Starting Rise Vison Station Setup"

		echo -n "Enter a hostname:"
		read hostname
		echo ""
		
		echo -n "Enter an IP Address: "
		read ip
		echo "";
		
		echo -n "Enter a gateway Address: ";
		read gateway
		echo "";
		
		echo -n "Enter a DNS Address: ";
		read dns
		echo ""
		
		echo ""
		echo "Using hostname: $hostname"
		echo "Using IP: $ip"
		echo ""
		
		sudo nmcli c mod 'Wired connection 1' ipv4.addresses $ip/24 ipv4.method manual
		sudo nmcli c mod 'Wired connection 1' ipv4.gateway $gateway
		sudo nmcli c mod 'Wired connection 1' ipv4.dns $dns
		sudo nmcli c down 'Wired connection 1' && sudo nmcli c up 'Wired connection 1'
		
		echo "Giving some time for NTP to update..."
		sleep 30
		echo "Proceeding."

		sudo apt update; 
		sudo apt upgrade -y;
		sudo apt install -y unattended-upgrades unclutter;
		sudo apt autoremove -y

		echo "US/Central" > sudo tee /etc/timezone
		echo "$hostname" > sudo tee /etc/hostname
		
		echo "1 2 * * * root /sbin/reboot" | sudo tee -a /etc/cron.d/restart
		
		
		echo -n  "hostname=$hostname
		ip=$ip
		gateway=$gateway
		dns=$dns" > ~/.rise.config1;
		
		echo "
tmpfs    /tmp        tmpfs      defaults,noatime,mode=1777,size=500m    0    0
tmpfs    /var/log    tmpfs      defaults,noatime,mode=1777,size=500m    0    0
tmpfs    /var/tmp    tmpfs      defaults,noatime,mode=1777,size=100m    0    0" | sudo tee -a /etc/fstab
		
		touch ~/aptupgrade.txt
		sudo reboot
	fi
fi
