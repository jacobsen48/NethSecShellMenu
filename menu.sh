#!/bin/bash

#
# Copyright (C) 2024 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-2.0-only
#

# Function that give chance to read output of commands to the user, after given
# ENTER input, the menu continue with commands.
function toContinue {
  echo -e "\nPress ENTER to continue. \n"
  read -r
}

# Function that ask the user a confirm, this is to avoid a lot of redundant
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

# Function that list all the devices
function listDevices {
  data=$(/usr/libexec/rpcd/ns.devices call list-devices)
  device_names=$(echo "$data" | jq -r '.all_devices[] | select(.[".type"] == "device") | .name')

  echo "$device_names"
}

# Function that listed all the devices give you the possibility of a choice
function selectDevice {

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
        echo "$selected_device"
        break
      else
        echo "Invalid selection. Try again."
      fi
    done
  fi
}

# Function the list the interfaces  
function listInterfaces {
  config_file=$(cat /etc/config/network)

  config_file=$(echo "$config_file" | sed -e '/config interface '\''loopback'\''/,/config interface/!b' -e '/config interface/!d' -e '/config interface '\''loopback'\''/d')
  #interfaces_and_devices=$(echo "$config_file" | grep -E "(config interface|option device)")
  config_file=$(echo "$config_file" | grep -E "(config interface|option device)")

  config_file=$(echo "$config_file" | grep -E "config interface")
  interfaces=$(echo "$config_file" | awk -F "'" '{print $2}')

  echo "$interfaces"
}

#
function selectInterface {
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
        echo "$selected_interface"
        break
      else
        echo "Invalid selection. Try again."
      fi
    done
  fi
}

# Function that perform a backup
function backup {
  echo "System backup will be performed"
  if confirm; then
    echo " Updating System ... "
    /usr/libexec/rpcd/ns.backup call backup
  fi
}

# Function that will reset the system to factory defaults
function default {
  echo "You are about to reset the firewall to factory defaults.
  The firewall will shutdown directly after completion."
  if confirm; then
    echo
    /usr/sbin/remove-storage
    /sbin/firstboot -y
  fi
}

# Function that perform a shutdown of the system
function poweroff {
  echo "The system will halt and poweroff."
  if confirm; then
    echo
    /usr/libexec/rpcd/ns.power call poweroff
  fi
}

# Function that give chance to change root password
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

# Function that given domain or ip, it perform a ping.
function pingHost {
  echo "Enter a host name or IP address"
  read -r pinghost
  ping -c 3 -n "$pinghost"
}

# Function that will perform a reboot of the system
function reboot {
  echo "The system will reboot."
  if confirm; then
    echo
    /usr/libexec/rpcd/ns.power call reboot
  fi
}

# Function that perform an update of the system if necessary.
function update {
  echo " Checking Update ... "
  check=$(/usr/libexec/rpcd/ns.update call check-system-update)

  CURRENT_VERSION=$(echo "$check" | sed -n 's/.*"currentVersion": "\([^"]*\)".*/\1/p')
  LAST_VERSION=$(echo "$check" | sed -n 's/.*"lastVersion": "\([^"]*\)".*/\1/p')

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

# Function that print a banner that contain info about the producer
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

# Function that create a vlan
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

# Function used to delete a device (vlan)
function deleteDevice {
  echo
  echo "Delete Device"		
  echo

  selected_device=$(selectDevice)

  j='{"action": "delete-device", "device_name": "'"$selected_device"'"}'
  echo "$j"
  echo "$j" | python /usr/libexec/rpcd/ns.devices call delete-device
}

# Function needed to unconfigure devices removing interface from them
function unconfigureDevice {
  echo
  echo "Unconfigure Device"		
  echo "Here you have to chose the interfaces linked to the device"
  echo "After all the interfaces of a certain device will be deleted"
  echo "The Device is to consider unconfigured"
  echo

  selected_interface=$(selectInterface) 

  j='{"iface_name": "'"$selected_interface"'"}'
  echo "$j"
  echo "$j" | python /usr/libexec/rpcd/ns.devices call unconfigure-device
}

# Function Bridge configuration
function bridgeConf() {
  function listZones {
    data=$(/usr/libexec/rpcd/ns.devices call list-zones-for-device-config)
    zones_names=$(echo "$data" | jq -r '.zones[] | .name')

    echo "$zones_names"
  }

  function selectZone {

    zones_names=$(listZones)

    if [ -z "$zones_names" ]; then
      echo "Zone not found."
    else
      zone_array=()
      for zone_name in $zones_names; do
        zone_array+=("$zone_name")
      done

      PS3="Select zone name: "

      select selected_zone in "${zone_array[@]}"; do
        if [ -n "$selected_zone" ]; then
          echo "$selected_zone"
          break
        else
          echo "Invalid selection. Try again"
        fi
      done
    fi
  }

  selectedZone=$(selectZone)
  
  read -p "Insert name of the logical inteface: " -r interface_name
  echo

  echo "Protocol: "
  echo "1) static"
  echo "2) dhcp"
  echo "3) dhcpv6"
  echo
  read -p "Enter an option: " -r OPCODE
  echo

  case ${OPCODE} in
    1)
      protocol="static"
      ;;
    2)
      protocol="dhcp"
      ;;
    3)
      protocol="dhcpv6"
      ;;
    *)
      echo "Invalid option"
      ;;
  esac
  echo "$protocol"
  echo

  ipv6="false"

  if [ "$protocol" == "static" ]; then
    echo "IP address with CIDR annotation"
    read -p "Insert: " -r IP
    # echo "Do you want to enable ipv6?"
    # read -p "[y/N]" -r response
    # case $response in
    #   [Yy]* ) ipv6="true";;
    #   [Nn]* ) ipv6="false";;
    #   * ) echo "Invalid response.";;
    # esac
    # if [ "$ipv6" == "true" ]; then
    #   read -p "Insert IPv6 address: " -r IP6
    # fi
  elif [[ "$protocol" == "dhcp" ]]; then
    echo "$protocol"
    echo
    echo "Hostname to send when requesting DHCP"
    echo 
    echo "1) Send the hostname of this device"
    echo "2) Do not send a hostname"
    echo "3) Send a a custom hostname"
    read -p "Enter an option: " -r OPCODE
    echo

    case ${OPCODE} in
      1)
        dhcp_hostname_to_send="deviceHostname"
        ;;
      2)
        dhcp_hostname_to_send="doNotSendHostname"
        ;;
      3)
        dhcp_hostname_to_send="customHostname"
        read -p "Insert the custom hostname" -r custom_hostname
        ;;
      *)
        echo "Invalid option"
        ;;
    esac

  elif [[ "$protocol" == "dhcpv6" ]]; then
    echo "$protocol"
  else
    echo "Protocollo non valido."
  fi

  echo '{ 
  "device_name":"", 
  "device_type":"logical",
  "interface_name":"'"$interface_name"'",
  "protocol":"'"$protocol"'",
  "zone":"'"$selectedZone"'",
  "logical_type":"'"$1"'",
  "interface_to_edit":"",
  "ip4_address":"'"$IP"'",
  "ip4_gateway":"",
  "ip4_mtu":"",
  "ip6_enabled":"'"$ipv6"'",
  "ip6_address":"",
  "ip6_gateway":"",
  "ip6_mtu":"",
  "attached_devices":["'"$2"'"],
  "bonding_policy":"",
  "bond_primary_device":"",
  "pppoe_username":"",
  "pppoe_password":"",
  "dhcp_client_id":"",
  "dhcp_client_id":"",
  "dhcp_hostname_to_send":"'"$dhcp_hostname_to_send"'",
  "dhcp_custom_hostname":"'"$custom_hostname"'"
}' | jq . | /usr/libexec/rpcd/ns.devices call configure-device
} 

# Function bond configuratio
function bondConf {

  conf='{}'

  echo "$conf"
}


# Function needed to configure a device, creating an interface on them
function configureDevice {
  echo
  echo "Configure Device"
  echo

  echo 
  echo "Choose the logical type: "
  echo "1) bridge 2) bond"
  read -p "Enter an option: " -r logt

  echo "Select the device to configure"
  selectedDevice=$(selectDevice)
  echo

  case $logt in
    1)
      logical_type="bridge"
      bridgeConf "$logical_type" "$selectedDevice"
      ;;

    2)
      logical_type="bond"
      bondConf "$logical_type" "$selectedDevice"
      ;;

    *)
      echo "Invalid option"
      echo
      ;;
  esac

}

# Function for the Interfaces and devices menu
function iad {

  condition="true"

  while $condition; do

    echo " --- Interfaces and Devices --- "
    echo " Remember to commit for the changes to take effect"
    echo " 0) Back to Main Menu"
    echo " 1) Create vlan device   5) Configure device"
    echo " 2) Delete vlan device   6) Unconfigure device"
    echo " 3) List devices         7) Uci Changes"    
    echo " 4) List interfaces      8) Uci Commit"
    echo
    read -p "Choose an option: " -r response
    case $response in
      1)
        vlanCreation
        toContinue
        clear
        ;;

      2)
        deleteDevice
        toContinue
        clear
        ;;

      3)
        listDevices
        toContinue
        clear
        ;;

      4)
        listInterfaces
        toContinue
        clear
        ;;

      5)
        configureDevice
        toContinue
        clear
        ;;

      6)
        unconfigureDevice
        toContinue
        clear
        ;;

      7)
        uci changes
        toContinue
        clear
        ;;

      8)
        uci commit 
        toContinue
        clear
        ;;

      0)
        condition="false"
        ;;

      *)
        echo "Invalid Option"
        clear
        ;;
    esac
  done
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
    echo " 0) Logout "
    echo " 1) Interface and device        7) Ping Host "
    echo " 2) Reset the root password     8) Shell "
    echo " 3) Reset to factory defaults   9) Bwm-ng "
    echo " 4) Power off System           10) Log "
    echo " 5) Reboot System              11) Backup "
    echo " 6) SpeedTest                  12) Update from console "
    echo
    read -p "Enter an option: " -r OPCODE
    echo

    set +e

    case ${OPCODE} in
      0|exit|logout|quit)
        exit
        ;;
      1)
        clear
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
        echo "Invalid option"
        clear
        ;;
    esac

  done
}

menu
