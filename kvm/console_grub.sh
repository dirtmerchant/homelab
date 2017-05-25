 #! /bin/bash
 
 sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"|GRUB_CMDLINE_LINUX_DEFAULT="quiet splash console=ttyS0,38400n8 console=tty0"|' /etc/default/grub && sudo update-grub
