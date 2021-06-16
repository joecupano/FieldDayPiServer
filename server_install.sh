#!/bin/bash

###
### Field Day Pi Server Install
###
### 

##
## REVISION: 20210614-2100
## 


##
## INIT VARIABLES 
##

# GitHub Repos
fielddaypiserv_github_repo="https://github.com/joecupano/FieldDayPiServer.git"


##
##  START 
##

echo " "
echo "Field Day Pi Server Install"
echo " "
echo "- Ensure Operating System is up to date"
echo " "
sudo apt-get update
sudo apt-get -y upgrade
#echo " "
#echo "- Disable WiFi and Bluetooth"
#echo " "
#sudo cat << EOF >> /boot/config.txt
#dtoverlay=disable-wifi
#dtoverlay=disable-
#EOF
sleep 3
echo " "
echo "- Update Static IP Address"
echo " "
sudo cat << EOF >> /etc/dhcpcd.conf

### added by server_script.sh ###
interface eth0
arping 192.168.15.1
arping 192.168.73.1

# Field Day Static IP configuration:
profile 192.168.73.1
static ip_address=192.168.73.100/24
static routers=192.168.73.1
static domain_name_servers=192.168.73.1

# Home Network
profile 192.168.15.1
static ip_address=192.168.10.75/21
static routers=192.168.15.1
static domain_name_servers=192.168.15.1 
EOF
sleep 3
echo " "
echo "- Add Field Day Log Account"
echo " "
sudo adduser fieldday
echo " "
echo "- Install Windows File Server (Samba)"
echo " "
sudo apt-get -y install samba samba-common-bin
sleep 3
sudo cat << EOF >> /etc/samba/smb.conf
[fieldday]
path = /home/fieldday
writeable=yes
create maskd=0775
directory mask=0775
public=no

[pi]
path = /home/pi
writeable=yes
create maskd=0775
directory mask=0775
public=no
EOF
echo " "
echo "- Add pi password to Windows File Server"
echo " "
sudo smbpasswd -a pi
echo " "
echo "- Add fieldday password to Windows File Server"
echo " "
sudo smbpasswd -a fieldday
echo " "
echo "- Start Windows File Server"
echo " "
sudo systemctl restart smbd
echo " "
echo "- Install Web Server (nginx)"
echo " "
sleep 3
sudo apt-get -y install nginx
##echo " "
##echo "- Generate self-signed SSL certificate --  /C=US/ST=New York/L=Hudson Valley/O=Hudson Valley Digital Network/OU=HASviolet/CN=hvdn.org"
##echo " "
##sudo openssl req -x509 -nodes -days 1095 -newkey rsa:2048 -subj "/C=US/ST=New York/L=Hudson Valley/O=Hudson Valley Digital Network/OU=HASviolet/CN=hvdn.org" -keyout /etc/ssl/private/fielddaypiserver.key -out /etc/ssl/private/fielddaypiserver.crt
echo " "
echo "- Copy sample web pages into /var/www/html"
echo " "
sudo cp ~/FieldDayPiServer/sample-web-site/* /var/www/html
echo " "
echo "- Start Web Server (nginx)"
echo " "
sudo systemctl start nginx
echo " "
echo " "
echo "Field Day Pi Server install Complete"
echo " "
echo " Be sure to create/add all web pages/files in the /var/www/html directory"
echo " "
echo "- Enjoy!"
echo " "
exit 0
