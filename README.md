# Field Day Pi Server

How to build a Field Day Server using a Raspberry Pi.

## Overview

This server build provides the following services:

- Windows File Server (Samba) for hosting a shared log file
  
  - N3FJP ARRL Fied Day Contest Log server

- Web Server for hosting web pages that provide use information for Field Day participants
  
  - Site Operations info
  
  - Software repo for use by participants

## Audience

These instructions are targeted for thos experienced with Linux and the Raspberry Pi.

## Specification

Raspberry Pi 3B or better

16GB microSD Class 10 card

## Create Image

- Install Raspberry Pi OS Lite (32-bit) to the microSD card. ([Raspberry Pi Imager](https://www.raspberrypi.org/software/) recommended)

## Configure Pi

- Log into the pi and run <mark>sudo raspi-config</mark>

- Within raspi-config go through the following menus and selections

```
1 System Options > S3 Password
1 System Options > S4 Hostname
1 System Options > B1 Console
3 Interface Options > P2 SSH > Yes
4 Performance Options > P2 GPU Memory > 16
5 Localisation Options > L1 Locale > YOUR-LOCALE
  Wait a while . . . 
5 Localisation Options > L2 Timezone > YOUR-TIMEZONE
5 Localisation Options > L3 Keyboard

5 Localisation Options > L4 WLAN Country > YOUR-COUNTRY
6 Advanced Options > A1 Expand Filesystem 
6 Advanced Options > A4 Network Interface Names > N
  Finish > Yes to reboot

```

- Once rebooted, log in as pi then copy the <mark>server_install.sh</mark> shell script from the repo into the pi home directory and run.


