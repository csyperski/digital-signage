# 1|0 -> 1=false/off 0=true/on
raspi-config nonint get_can_expand
raspi-config nonint do_expand_rootfs
raspi-config nonint get_hostname
raspi-config nonint do_hostname "yourhostname"
raspi-config nonint get_boot_cli
raspi-config nonint get_autologin
raspi-config nonint do_boot_behaviour B1
raspi-config nonint do_boot_behaviour B2
raspi-config nonint do_boot_behaviour B3
raspi-config nonint do_boot_behaviour B4
raspi-config nonint get_boot_wait
raspi-config nonint do_boot_wait 1|0
raspi-config nonint get_boot_splash
raspi-config nonint do_boot_splash 1|0
raspi-config nonint get_overscan
raspi-config nonint do_overscan 1|0
raspi-config nonint get_pixdub
raspi-config nonint do_pixdub 1|0
raspi-config nonint get_camera
raspi-config nonint do_camera 1|0
raspi-config nonint get_ssh
raspi-config nonint do_ssh 1|0
raspi-config nonint get_vnc
raspi-config nonint do_vnc 1|0
raspi-config nonint get_spi
raspi-config nonint do_spi 1|0
raspi-config nonint get_i2c
raspi-config nonint do_i2c 1|0
raspi-config nonint get_serial
raspi-config nonint get_serial_hw
raspi-config nonint do_serial 1|0
raspi-config nonint get_onewire
raspi-config nonint do_onewire 1|0
raspi-config nonint get_rgpio
raspi-config nonint do_rgpio 1|0
raspi-config nonint get_blanking
raspi-config nonint do_blanking 1|0
raspi-config nonint get_pi_type
raspi-config nonint is_pi
raspi-config nonint is_pifour
raspi-config nonint is_fkms
raspi-config nonint get_config_var arm_freq /boot/config.txt
raspi-config nonint do_overclock None|Modest|Medium|High|Turbo
raspi-config nonint get_config_var gpu_mem /boot/config.txt
raspi-config nonint get_config_var gpu_mem_256 /boot/config.txt
raspi-config nonint get_config_var gpu_mem_512 /boot/config.txt
raspi-config nonint get_config_var gpu_mem_1024 /boot/config.txt
raspi-config nonint do_memory_split 16|32|64|128|256
raspi-config nonint get_config_var hdmi_group /boot/config.txt
raspi-config nonint get_config_var hdmi_mode /boot/config.txt
raspi-config nonint get_wifi_country
# find wifi countries here /usr/share/zoneinfo/iso3166.tab
raspi-config nonint do_wifi_country "yourcountry"
raspi-config nonint do_pi4video V1
raspi-config nonint do_pi4video V2
raspi-config nonint do_pi4video V3
raspi-config nonint get_pi4video
raspi-config nonint get_overlay_now
raspi-config nonint get_overlay_conf
raspi-config nonint get_bootro_conf
raspi-config nonint enable_overlayfs
raspi-config nonint disable_overlayfs
raspi-config nonint enable_bootro
raspi-config nonint disable_bootro
raspi-config nonint is_uname_current
raspi-config nonint list_wlan_interfaces
raspi-config nonint is_installed realvnc-vnc-server
raspi-config nonint is_installed xscreensaver
vcgencmd get_mem gpu | cut -d = -f 2 | cut -d M -f 1
echo \"$SUDO_USER:%s\" | chpasswd
