set autoload no
set serverip 10.0.56.1
set bootfile irpi
set loadaddr 7FE0
if usb start; then
	set ipaddr 10.0.56.100;
	set netmask 255.255.255.0;
	if tftpboot ${loadaddr} irpi; then
		go 8000;
	fi;
fi;
