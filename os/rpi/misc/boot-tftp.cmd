set autoload no
set serverip 10.0.55.110
set bootfile irpi
set loadaddr 7FE0
if usb start; then
	if dhcp; then
		if tftpboot ${loadaddr} irpi; then
			go 8000;
		fi;
	fi;
fi;
