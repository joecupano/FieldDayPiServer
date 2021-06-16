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

Raspberry Pi 3B or better

16GB microSD Class 10 card

## Create Image

- Install Raspberry Pi OS Lite (32-bit) to the microSD card. ([Raspberry Pi Imager](https://www.raspberrypi.org/software/) recommended)

## Configure Pi

- Log into the pi and run <mark>sudo raspi-config</mark>

- Within raspi-config make changes for your locale and the following:
-- Under Performance Options set GPU Memory for 16 
-- Under Advanced Options set Network Interface Names to No
-  Select Finish then Yes to reboot

- Once rebooted, log in as pi then copy the <mark>server_install.sh</mark> shell script from the repo into the pi home directory and run.
- Create any web pages/files in the /var/www/html directory. See sample-web-site directory in repo for some inspiration.



