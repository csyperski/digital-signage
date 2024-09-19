#!/bin/bash


if [ -f ~/.rise.config ]; then
	echo "This script has already been executed";
	exit 1;
fi

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
sleep 5
echo "Proceeding."

sudo apt update; 
sudo apt upgrade -y;
sudo apt install -y unattended-upgrades;
sudo apt autoremove -y

echo "US/Central" > sudo tee /etc/timezone
echo "$hostname" > sudo tee /etc/hostname

echo "1 2 * * * root /sbin/reboot" | sudo tee -a /etc/cron.d/restart


echo -n  "hostname=$hostname
ip=$ip
gateway=$gateway
dns=$dns" > ~/.rise.config;

echo "Configuring power management..." 
sudo raspi-config nonint do_blanking 1
echo "done"

sudo wget -O /usr/share/rpd-wallpaper/fisherman.jpg https://www.dupage88.net/site/public/agoraimages/?item=18485
sudo wget https://github.com/seffs/wayfire-plugins-extra-raspbian/releases/download/v0.7.5/wayfire-plugins-extra-raspbian-aarch64.tar.xz
sudo tar xf wayfire-plugins-extra-raspbian-aarch64.tar.xz -C /

echo '[core]
plugins = \
        autostart \
        hide-cursor

[autostart]
kiosk = ~/kiosk.sh' | sudo tee -a .config/wayfire.ini

echo '#!/bin/bash
/home/admin/rvplayer/scripts/start.sh' | tee ~/kiosk.sh

chmod +x ~/kiosk.sh

cd ~
wget https://storage.googleapis.com/install-versions.risevision.com/installer-lnx-arm64.sh
chmod +x installer-lnx-arm64.sh
./installer-lnx-arm64.sh --accept
sudo tar xf wayfire-plugins-extra-raspbian-aarch64.tar.xz -C /
