# Field Day Pi Server

How to build a Field Day Server using a Raspberry Pi.

## Overview

This server build provides the following services:

- Windows File Server (Samba) for hosting a shared or dedicated log files
  
- Web Server for hosting web pages that provide use information for Field Day participants
  
  - Site Operations info
  
  - Software repo for use by participants

## Audience

These instructions are targeted for thos experienced with Linux and the Raspberry Pi.

## Specification

- Raspberry Pi 3B or better
- 16GB microSD Class 10 card

## Create Image

- Install Raspberry Pi OS Lite (32-bit) to the microSD card. ([Raspberry Pi Imager](https://www.raspberrypi.org/software/) recommended)

## Configure Pi

- Log into the pi and run raspi-config
```
   sudo raspi-config
```
- Within raspi-config make the following changes:
-- Change password for the 'pi' user
-- Change hostname
-- Boot to text console requiring user to login
-- Enable remote command line access using ssh
-- Set GPU Memory for 16
-- Configure langage and regional settings (timezone should be local)
-- Set Predictable Network Interface Names to No
-- Select Finish then Yes to reboot

- Once rebooted, log in as pi
- Install git
```
   sudo apt-get -y install git
```
- Clone repo
```
   git clone https://github.com/joecupano/FieldDayPiServer.git
```
- Change directory into cloned repo and run script
```
   ./server_install.sh
```
- To allow pi and fieldday home directoires to accessibale via windows file share, append the following lines into /etc/samba/smb.conf
```
### added by server_script.sh ###
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
```
- Restart windows file share
'''
sudo systemctl restart smbd
'''
- Update/Create any web pages/files in the /var/www/html directory. See sample-web-site directory in repo for some inspiration.



