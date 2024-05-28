#!/bin/bash

#
# Copyright (C) 2024 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-2.0-only
#

function toContinue {
  echo -e "\nPress ENTER to continue. \n"
  read -r
}

function confirm {
  while true; do
    read -p "Do you want to proceed? [y/N] " -r response
    case $response in
      [Yy]* ) return 0;;
      [Nn]* ) return 1;;
      * ) echo "Invalid response. Answer with 'y' o 'N'.";;
    esac
  done	
}

function listDevices {
  data=$(/usr/libexec/rpcd/ns.devices call list-devices)
  device_names=$(echo "$data" | jq -r '.all_devices[] | select(.[".type"] == "device") | .name')

  echo "$device_names"
}

# function listInterfaces {
#   config_file="/etc/config/network"
#
#   interfaces=()
#   devices=()
#
#   while read -r line; do
#     if [[ $line == config\ interface* ]]; then
#       interface=$(echo "$line" | awk -F "'" '{print $2}')
#       if [[ $interface != "loopback" ]]; then
#         interfaces+=("$interface")
#       fi
#     elif [[ $line == option\ device* ]]; then
#       device=$(echo "$line" | awk '{print $3}' | tr -d "'")
#       if [[ $device != "lo" ]]; then
#         devices+=("$device")
#       fi
#     fi
#   done < "$config_file"
#
#   for (( i = 0; i<${#interfaces[@]}; i++ )); do
#     echo "$((i+1)). ${interfaces[$i]} (Device: ${devices[$i]})"
#   done
#
#   echo "$interfaces"
# }

function listInterfaces {
  config_file=$(cat /etc/config/network)

  config_file=$(echo "$config_file" | sed -e '/config interface '\''loopback'\''/,/config interface/!b' -e '/config interface/!d' -e '/config interface '\''loopback'\''/d')
  #interfaces_and_devices=$(echo "$config_file" | grep -E "(config interface|option device)")
  config_file=$(echo "$config_file" | grep -E "(config interface|option device)")

  config_file=$(echo "$config_file" | grep -E "config interface")
  interfaces=$(echo "$config_file" | awk -F "'" '{print $2}')

  echo "$interfaces"
}

function backup {
  echo "System backup will be performed"
  if confirm; then
    echo " Updating System ... "
    /usr/libexec/rpcd/ns.backup call backup
  fi
}

function default {
  echo "You are about to reset the firewall to factory defaults.
  The firewall will shutdown directly after completion."
  if confirm; then
    echo
    /usr/sbin/remove-storage
    /sbin/firstboot -y
  fi
}

function poweroff {
  echo "The system will halt and poweroff."
  if confirm; then
    echo
    /usr/libexec/rpcd/ns.power call poweroff
  fi
}


function rootPass {
  USER_NAME=root

  echo "The root user password will change."
  if confirm; then
    echo
    if [ "$response" = "y" ]; then
      echo
      read -p " Insert new password: " -r pass1
      echo
      read -p " Confirm password: " -r pass2
      echo
      if [ "$pass1" = "$pass2" ]; then
        j='{"username": "'$USER_NAME'", "password": "'"$pass2"'"}'
        echo "$j"
        echo "$j" | python /usr/libexec/rpcd/ns.account call set-password
      else
        echo " Passwords do not match "	
      fi
    fi
  fi
}

function pingHost {
  echo "Enter a host name or IP address"
  read -r pinghost
  ping -c 3 -n "$pinghost"
}

function reboot {
  echo "The system will reboot."
  if confirm; then
    echo
    /usr/libexec/rpcd/ns.power call reboot
  fi
}

function update {
  echo " Checking Update ... "
  prova=$(/usr/libexec/rpcd/ns.update call check-system-update)

  CURRENT_VERSION=$(echo "$prova" | sed -n 's/.*"currentVersion": "\([^"]*\)".*/\1/p')
  LAST_VERSION=$(echo "$prova" | sed -n 's/.*"lastVersion": "\([^"]*\)".*/\1/p')

  if [ -z "$LAST_VERSION" ]; then
    echo "System already up to date to the newest version"
    echo "$CURRENT_VERSION"
    exit
  else
    echo "There is an update"
    echo " Current version: $CURRENT_VERSION
    Last version: $LAST_VERSION" 
  fi

  echo "The upgrade will be performed."

  if confirm; then
    echo " Updating System and Reboot ...  "
    /usr/libexec/rpcd/ns.update call update-system
  fi

}

function banner {
  file="/etc/os-release"

  PRETTY_NAME=$(grep -oP 'PRETTY_NAME="\K[^"]*' "$file") 
  HOME_URL=$(grep -oP 'HOME_URL="\K[^"]*' "$file")
  NS_URL=$(grep -oP 'OPENWRT_DEVICE_MANUFACTURER_URL="\K[^"]*' "$file")

  echo
  echo "------------------------------------------------------"
  echo "-                                                    -"
  echo "-                       Welcome                      -"
  echo "-      $PRETTY_NAME    	     -"
  echo "-      $HOME_URL    -"
  echo "-      $NS_URL                	     -"
  echo "-                                                    -"
  echo "------------------------------------------------------"
  echo

  # Parse the JSON and look for the IP addresses associated with "wan" and "lan"
  extract_ips() {
    local zone=$1
    local json=$2
    local ipa

    ipa=$(echo "$json" | jq -r ".all_devices[] | select(.iface.\".name\" == \"$zone\") | .ipaddrs[0].address")
    echo "$ipa"
  }

  json_data=$(/usr/libexec/rpcd/ns.devices call list-devices | jq)

  ip_wan=$(extract_ips "wan" "$json_data")
  ip_lan=$(extract_ips "lan" "$json_data")

  # Print IP addresses:
  #echo "IP per wan: $ip_wan"
  #echo "IP per lan: $ip_lan"

  echo " WAN --> $ip_wan "
  echo " LAN --> $ip_lan "
  echo
}

function iad {

  function vlanCreation {
    echo
    echo "Vlan creation"
    echo

    PS3="Seleziona vlan_type: "
    options=("802.1q" "802.1ad")
    select a in "${options[@]}"
    do
      case $a in
        "802.1q")
          echo "802.1q Selected"
          break
          ;;
        "802.1ad")
          echo "802.1ad Selected"
          break
          ;;
        *)
          echo "Invalid option. Try again."
          ;;
      esac
    done

    interface_array=()
    for interface in /sys/class/net/*; do
      interface_name=$(basename "$interface")
      if [[ $interface_name != "bonding_masters" && $interface_name != "ifb-dns" && $interface_name != "lo" ]]; then
        interface_array+=("$interface_name")
      fi
    done

    PS3="Select base_device_name: "
    select b in "${interface_array[@]}"
    do
      case $b in
        *)
          echo "$b Selected"
          break
          ;;
      esac
    done


    read -p "Insert vlan_id (must be between 1 and 4096): " -r c
    while ! [[ "$c" =~ ^[0-9]+$ ]] || (( c < 1 || c > 4096 )); do
      echo "vlan_id not valid. Must be between 1 and 4096."
      read -p "Insert vlan_id: " -r c
    done

    j='{"vlan_type": "'"$a"'", "base_device_name": "'"$b"'", "vlan_id": "'"$c"'"}'
    echo "$j" | python /usr/libexec/rpcd/ns.devices call create-vlan-device

    echo "$j"
  }

  function deleteDevice {
    echo
    echo "Delete Device"		
    echo

    device_names=$(listDevices)

    if [ -z "$device_names" ]; then
      echo "Devices not found."
    else
      device_array=()
      for device_name in $device_names; do
        device_array+=("$device_name")
      done

      PS3="Select device name: "

      select selected_device in "${device_array[@]}"; do
        if [ -n "$selected_device" ]; then
          j='{"action": "delete-device", "device_name": "'"$selected_device"'"}'
          echo "$j"
          echo "$j" | python /usr/libexec/rpcd/ns.devices call delete-device
          break
        else
          echo "Invalid selection. Try again."
        fi
      done
    fi
  }

  function configureDevice {
    echo
    echo "Configure Device"
    echo
  }

  function unconfigureDevice {
    echo
    echo "Unconfigure Device"		
    echo "Here you have to chose the interfaces linked to the device"
    echo "After all the interfaces of a certain device will be deleted"
    echo "The Device is to consider unconfigured"
    echo

    interface_names=$(listInterfaces)

    if [ -z "$interface_names" ]; then
      echo "Devices not found."
    else
      interface_array=()
      for interface_name in $interface_names; do
        interface_array+=("$interface_name")
      done

      PS3="Select interface name: "

      select selected_interface in "${interface_array[@]}"; do
        if [ -n "$selected_interface" ]; then
          j='{"device_name": "'"$selected_interface"'"}'
          echo "$j"
          echo "$j" | python /usr/libexec/rpcd/ns.devices call unconfigure-device
          break
        else
          echo "Invalid selection. Try again."
        fi
      done
    fi
  }

  echo " --- Interfaces and Devices --- "
  echo " 1) Create vlan device   5) Configure device"
  echo " 2) Delete device        6) Unconfigure device"
  echo " 3) List devices         7) Uci Commit"    
  echo " 4) List interfaces      0) Back to Main Menu"
  echo
  read -p "Choose an option: " -r response
  case $response in
    1)
      vlanCreation
      ;;

    2)
      deleteDevice
      ;;

    3)
      listDevices
      ;;

    4)
      listInterfaces
      ;;

    5)
      configureDevice
      ;;

    6)
      unconfigureDevice
      ;;

    7)
      uci commit 
      ;;

    0)
      exit
      ;;
    *)
      echo "Invalid Option"
      ;;
  esac

}

function menu {
  trap : 2
  trap : 3

  if [ "$(id -u)" != "0" ]; then
    echo "Must be root"
    exit 1
  fi

  while : ; do

    banner

    set -e

    echo
    echo " 0) Logout                      7) Ping Host "
    echo " 1) Interface and device        8) Shell "
    echo " 2) Reset the root password     9) bwm-ng "
    echo " 3) Reset to factory defaults  10) Log "
    echo " 4) Power off system           11) Backup "
    echo " 5) Reboot System              12) Update from console "
    echo " 6) speedTest "
    echo
    read -p "Enter an option: " -r OPCODE
    echo

    set +e

    case ${OPCODE} in
      0|exit|logout|quit)
        exit
        ;;
      1)
        iad
        toContinue
        clear
        ;;
      2)
        rootPass
        toContinue
        clear
        ;;
      3)
        default
        toContinue
        clear
        ;;
      4)
        poweroff
        toContinue
        clear
        ;;
      5)
        reboot
        toContinue
        clear
        ;;
      6)
        curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python -
        toContinue
        clear
        ;;
      7)
        pingHost
        toContinue
        clear
        ;;
      8)
        bash
        toContinue
        clear
        ;;
      9)
        bwm-ng
        toContinue
        clear
        ;;
      10)
        tail -f /var/log/messages
        toContinue
        ;;
      11)
        backup
        toContinue
        clear
        ;;
      12)
        update
        toContinue
        clear
        ;;
      *)
        clear
        ;;
    esac

  done
}

menu
