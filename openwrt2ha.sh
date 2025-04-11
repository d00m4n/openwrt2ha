#!/bin/sh

DEBUG_MODE=0
VERSION="1.0.100"
PID_FILE="/var/run/openwrt2ha.pid"
# Get day of the week
DAY_OF_WEEK=$(date +%u)
LOG_FILE="/var/log/openwrt2ha-${DAY_OF_WEEK}.log"
ENV_FILE=/etc/openwrt2ha/.openwrt2ha.env
# timeout in seconds
MSG_TIMEOUT=5
# ----------------| command line arguments |----------------
# Check if --about parameter was passed
if [ "$1" = "--about" ]; then
    about $VERSION
fi
# Check if --debug parameter was passed
if [ "$1" = "--debug" ]; then
    DEBUG_MODE=1
fi
# ----------------| Logger funtion |----------------

log_message() {
    message="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    
    if [ $DEBUG_MODE -eq 1 ]; then
        # In debug mode, show on screen and write to file
        echo "$message" | tee -a "$LOG_FILE"
    else
        # In normal mode, only write to file
        echo "$message" >> "$LOG_FILE"
    fi
}
log_message "Log file: $LOG_FILE"
# Display the script title
clear
# Show the title of the script
header () {
    title="-| OPENWRT2HA v$VERSION |-"
    cols=80  # Fixed width
    padding=$(( (cols - ${#title}) / 2 ))
    left_padding=$(printf '%*s' "$padding" | tr ' ' '-')
    right_padding=$(printf '%*s' $(( cols - padding - ${#title} )) | tr ' ' '-')
    log_message '%s%s%s\n' "$left_padding" "$title" "$right_padding"
}

# Show information about the script
about() {
    local cols=80
    local version=$1
    local start_year="2025"
    local current_year=$(date +%Y)
    local copyright_years=""
    
    # Set copyright years format
    if [ "$start_year" = "$current_year" ]; then
        copyright_years="$start_year"
    else
        copyright_years="$start_year - $current_year"
    fi
    
    # Try to get terminal width
    if command -v stty >/dev/null 2>&1; then
        cols=$(stty size 2>/dev/null | cut -d' ' -f2)
        [ -z "$cols" ] && cols=80
    fi
    
    # Create the separator line
    local separator=$(printf '%*s' "$cols" | tr ' ' '-')
    
    # Print header
    echo "$separator"
    header
    echo "$separator"
    echo ""
    echo "This tool was developed by dr_d00m4n"
    echo "with assistance from Claude AI."
    echo ""
    echo "It provides a bridge between OpenWrt"
    echo "and Home Assistant, allowing for"
    echo "seamless integration of network"
    echo "devices into your smart home ecosystem."
    echo ""
    echo "Version: $version"
    echo "© $copyright_years dr_d00m4n"
    echo "All Rights Reserved"
    echo ""
    echo "ADDITIONAL INFORMATION:"
    echo "- GitHub: https://github.com/dr_d00m4n/openwrt2ha"
    echo "- License: MIT"
    echo "- Dependencies: ash, curl, ubus"
    echo ""
    echo "COMPONENT: $1"
    echo "- Status: Active"
    echo "- Last updated: $(date +%Y-%m-%d)"
    echo "$separator"
    exit 0
}

# Funció consistent per formatar SSIDs
format_ssid() {
    # Utilitza sed per assegurar una formatació consistent i eliminar possibles subratllats al final
    local formatted=$(echo "$1" | sed 's/[^a-zA-Z0-9_]/_/g')
    # Eliminem qualsevol subratllat al final
    formatted=$(echo "$formatted" | sed 's/_*$//')
    echo "$formatted"
}
check_host_ping() {
    local host="$1"
    local count="${2:-3}"    # Nombre d'intents (valor per defecte: 3)
    local timeout="${3:-2}"  # Timeout en segons (valor per defecte: 2)
    
    log_message "Checking connection to $host..."
    
    # Intentem fer ping a l'host
    if ping -c "$count" -W "$timeout" "$host" > /dev/null 2>&1; then
        log_message "✓ $host ok"
        return 0
    else
        log_message "✗ Error: no response from $host"
        return 1
    fi
}


# Show the title
header
# Function to log messages

log_message "Log file: $LOG_FILE"
# Load configuration from .env file if it exists

if [ -f $ENV_FILE ]; then
  . $ENV_FILE
  log_message "Loaded env: $ENV_FILE" 	 
else
  # Default configuration if no .env file
  log_message "Default config"
  MQTT_HOST="localhost"
  MQTT_PORT="1883"
  MQTT_USER=""
  MQTT_PASS=""
  HA_NAME=""
fi
log_message "Connection host: $MQTT_HOST:$MQTT_PORT"
check_host_ping $MQTT_HOST 1 1

# Get device description from samba configuration
DEVICE_DESCRIPTION=$(uci get samba4.@samba[0].description 2>/dev/null || echo "OpenWRT")
# Convert to uppercase and remove hyphens
DEVICE_FORMATTED=$(echo "$DEVICE_DESCRIPTION" | tr '[a-z]' '[A-Z]' | tr -d '-')
log_message "DEVICE_FORMATTED: $DEVICE_FORMATTED"
# Configure MQTT topics
MQTT_BASE="homeassistant"
: "${HA_NAME:=$DEVICE_DESCRIPTION}"
log_message "HA_NAME: $HA_NAME"
log_message "MQTT_BASE: $MQTT_BASE"


# Versió neta optimitzada per a publicació MQTT
publish_mqtt() {
    local topic=$1
    local message=$2
    local retain=$3
    if [ "$retain" = "retain" ]; then
        timeout $MSG_TIMEOUT mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" -t "$topic" -m "$message" -r 2>&1
         local result=$?
    else
        timeout $MSG_TIMEOUT mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" -t "$topic" -m "$message" 2>&1
        local result=$?
    fi
    
    case $result in
        0) : ;;
        127)
        DEBUG_MODE=1
        log_message "Bad configuration"
        exit $result
        ;;
        124) 
        DEBUG_MODE=1
        log_message "✗ Error: Timeout $timeout_segons segons"
        DEBUG_MODE=0
        exit $result
         ;;
        *) 
        DEBUG_MODE=1
        log_message "✗ Error (Code: $result)"
        DEBUG_MODE=0
        exit $result
      ;;
  esac
}

# Function to set up Home Assistant discovery for a WiFi network
setup_discovery_for_network() {
    local ssid=$1
    local device=$2
    local status=$3
    
    # Format the SSID for use in MQTT routes (replace spaces and special characters)
    # Utilitzem la funció format_ssid per assegurar consistència
    local ssid_formatted=$(format_ssid "$ssid")
    
    # Configure the discovery topic
    local discovery_topic="${MQTT_BASE}/switch/${DEVICE_FORMATTED}/${DEVICE_FORMATTED}_${ssid_formatted}/config"
    
    # Convert status from "on"/"off" to "ON"/"OFF" for Home Assistant
    local ha_status="OFF"
    if [ "$status" = "on" ]; then
        ha_status="ON"
    fi
    
    # Create the JSON payload for Home Assistant
    local discovery_payload='{
        "name": "'$ssid' WiFi",
        "state_topic": "'${MQTT_BASE}'/switch/'${DEVICE_FORMATTED}'/'${DEVICE_FORMATTED}_${ssid_formatted}'/state",
        "command_topic": "'${MQTT_BASE}'/switch/'${DEVICE_FORMATTED}'/'${DEVICE_FORMATTED}_${ssid_formatted}'/set",
        "payload_on": "ON",
        "payload_off": "OFF",
        "state_on": "ON",
        "state_off": "OFF",
        "device_class": "switch",
        "retain": true,
        "unique_id": "'${DEVICE_FORMATTED}'_'${ssid_formatted}'_wifi",
        "device": {
            "identifiers": ["'$DEVICE_FORMATTED'"],
            "name": "'$HA_NAME'",
            "model": "OpenWRT WiFi Control",
            "manufacturer": "OpenWRT"
        }
    }'
    
    # Publish the discovery configuration
    publish_mqtt "$discovery_topic" "$discovery_payload" "retain"
    
    # Publish initial state for this network
    publish_mqtt "${MQTT_BASE}/sensor/${DEVICE_FORMATTED}/availability" "online" "retain"
    publish_mqtt "${MQTT_BASE}/switch/${DEVICE_FORMATTED}/${DEVICE_FORMATTED}_${ssid_formatted}/state" "$ha_status" "retain"
}

# Funció per configurar el descobriment per al botó de reinici
# Funció per configurar el descobriment per al botó de reinici
setup_discovery_for_reboot_button() {
    # Identificador únic per al botó de reinici
    local button_id="reboot"
    
    # Configurem el tòpic de descobriment
    local discovery_topic="${MQTT_BASE}/button/${DEVICE_FORMATTED}/${DEVICE_FORMATTED}_${button_id}/config"
    
    # Creem el payload JSON per a Home Assistant
    local discovery_payload='{
        "name": "Reboot '${HA_NAME}'",
        "command_topic": "'${MQTT_BASE}'/button/'${DEVICE_FORMATTED}'/'${DEVICE_FORMATTED}_${button_id}'/set",
        "payload_press": "REBOOT",
        "device_class": "restart",
        "entity_category": "config",
        "unique_id": "'${DEVICE_FORMATTED}'_'${button_id}'_button",
        "device": {
            "identifiers": ["'$DEVICE_FORMATTED'"],
            "name": "'$HA_NAME'",
            "model": "OpenWRT Control",
            "manufacturer": "OpenWRT"
        }
    }'
    
    # Publiquem la configuració de descobriment
    publish_mqtt "$discovery_topic" "$discovery_payload" "retain"
}

# Funció per reiniciar el dispositiu OpenWRT
reboot_device() {
    # Publiquem un missatge de notificació abans de reiniciar
    publish_mqtt "${MQTT_BASE}/sensor/${DEVICE_FORMATTED}/reboot_status" "Reiniciant..." "retain"
    
    # Esperem 2 segons perquè el missatge es publiqui abans de reiniciar
    sleep 2
    
    # Executem el comandament de reinici
    reboot
}

# Function to publish the status of all WiFi networks
publish_wifi_status() {
    # Publish availability status for the device group
    publish_mqtt "${MQTT_BASE}/switch/${DEVICE_FORMATTED}/status" "online" "retain"
    
    # Get all WiFi interfaces
    interfaces=$(uci show wireless | grep "\.ssid=" | cut -d. -f1-2)
    
    # Publish the list of networks
    network_list=""
    
    for iface in $interfaces; do
        # Get the SSID
        ssid=$(uci get ${iface}.ssid)
        # Get the radio device using ifname
        device=$(uci -q get ${iface}.ifname || echo "wifi0")
        # Check if disabled
        disabled=$(uci -q get ${iface}.disabled || echo "0")
        
        # Determine status
        if [ "$disabled" = "1" ]; then
            status="off"
        else
            status="on"
        fi
        
        # Format SSID for the unique identifier - consistent formatting
        ssid_formatted=$(format_ssid "$ssid")
        # Create a unique identifier for this network
        unique_id="${DEVICE_FORMATTED}_${ssid_formatted}"

        # Add to the list
        if [ -z "$network_list" ]; then
            network_list="${ssid}:${device}:${status}"
        else
            network_list="${network_list},${ssid}:${device}:${status}"
        fi
        
        # Configure discovery for this WiFi network
        setup_discovery_for_network "$ssid" "$device" "$status"
    done
    
    # Configurem el botó de reinici
    setup_discovery_for_reboot_button
    
    # Publish the complete list to the networks topic
    publish_mqtt "${MQTT_BASE}/switch/${DEVICE_FORMATTED}/networks" "$network_list" "retain"
}

# Function to handle received messages
process_message() {
    topic="$1"
    message="$2"
    
    # Validació per assegurar que el missatge és correcte
    if [ -z "$topic" ] || [ -z "$message" ]; then
        # log_message "Error: Empty topic or message received"
        return
    fi
    
    # log_message "Processing message: '$message' from topic: '$topic'"
    
    # Comprovem si és una comanda per al botó de reinici
    if echo "$topic" | grep -q "^${MQTT_BASE}/button/${DEVICE_FORMATTED}/${DEVICE_FORMATTED}_reboot/set$"; then
        if [ "$message" = "REBOOT" ]; then
            reboot_device
        fi
        return
    fi
    
    # Expressió regular millorada que funciona amb la nova subscripció
    if echo "$topic" | grep -q "^${MQTT_BASE}/switch/${DEVICE_FORMATTED}/${DEVICE_FORMATTED}_[^/]*/set$"; then
        # Extreiem la part del tòpic que conté l'ID de la xarxa amb més precisió
        network_id=$(echo "$topic" | sed "s|^${MQTT_BASE}/switch/${DEVICE_FORMATTED}/\(${DEVICE_FORMATTED}_[^/]*\)/set|\1|")
        
        # log_message "Extracted network_id: $network_id"
        
        # Extreiem el SSID formatat de l'ID
        ssid_formatted=$(echo "$network_id" | sed "s|^${DEVICE_FORMATTED}_||")
        
        # log_message "Extracted SSID formatted: $ssid_formatted"
        
        # Busquem l'SSID original a partir del formatat
        interfaces=$(uci show wireless | grep "\.ssid=" | cut -d. -f1-2)
        ssid=""
        iface=""
        
        for i in $interfaces; do
            current_ssid=$(uci get ${i}.ssid)
            # Normalitzem els SSIDs formatats per comparació
            current_ssid_formatted=$(format_ssid "$current_ssid")
            ssid_formatted_to_match=$(format_ssid "$ssid_formatted")
            
            # log_message "Checking: $current_ssid -> $current_ssid_formatted vs $ssid_formatted_to_match"
            
            if [ "$current_ssid_formatted" = "$ssid_formatted_to_match" ]; then
                ssid="$current_ssid"
                iface="$i"
                break
            fi
        done
        
        if [ -z "$ssid" ]; then
            # log_message "Error: No SSID found for identifier $network_id"
            publish_mqtt "${MQTT_BASE}/switch/${DEVICE_FORMATTED}/${network_id}/error" "SSID not found" "retain"
            return
        fi
        
        # log_message "Found SSID: $ssid for interface: $iface"
        
        # The action will be "ON" or "OFF"
        action="$message"
        
        # Get the radio device
        device=$(uci -q get ${iface}.ifname || echo "")
        # If ifname doesn't exist, try device
        if [ -z "$device" ]; then
            device=$(uci -q get ${iface}.device || echo "")
        fi
        # log_message "Radio device: $device"
        # log_message "Action: $action"
        
        case "$action" in
            "ON")
                # Enable this specific WiFi network
                # log_message "Enabling WiFi $ssid($device)"
                uci set ${iface}.disabled='0'
                uci commit wireless
                
                # Apply changes by restarting this specific radio
                # log_message "Applying changes to device $radio_device"
                if [ -n "$radio_device" ]; then
                    # Utilitzem el nom correcte del dispositiu ràdio
                    # log_message "Executing: wifi up $radio_device"
                    wifi up $radio_device
                else
                    # If we can't identify the specific device, restart all WiFi
                    # log_message "Executing: wifi"
                    wifi
                fi
                
                # log_message "WiFi $ssid enabled"
                sleep 1  # Wait for changes to apply
                
                # Update state in Home Assistant
                publish_mqtt "${MQTT_BASE}/switch/${DEVICE_FORMATTED}/${network_id}/state" "ON" "retain"
                ;;
            "OFF")
                # Disable this specific WiFi network
                # log_message "Disabling WiFi $ssid"
                uci set ${iface}.disabled='1'
                uci commit wireless
                
                # Apply changes by restarting this specific radio
                # log_message "Applying changes to device $radio_device"
                if [ -n "$radio_device" ]; then
                    # Utilitzem el nom correcte del dispositiu ràdio
                    # log_message "Executing: wifi up $radio_device"
                    wifi up $radio_device
                else
                    # If we can't identify the specific device, restart all WiFi
                    # log_message "Executing: wifi"
                    wifi
                fi
                
                # log_message "WiFi $ssid disabled"
                sleep 1  # Wait for changes to apply
                
                # Update state in Home Assistant
                publish_mqtt "${MQTT_BASE}/switch/${DEVICE_FORMATTED}/${network_id}/state" "OFF" "retain"
                ;;
            *)
                # log_message "Unknown action: $action"
                publish_mqtt "${MQTT_BASE}/switch/${DEVICE_FORMATTED}/${network_id}/error" "Unknown action: $action" "retain"
                ;;
        esac
    # else
        # log_message "Topic does not match expected pattern: $topic"
        # log_message "Expected pattern: ${MQTT_BASE}/switch/${DEVICE_FORMATTED}/${DEVICE_FORMATTED}_[ssid]/set"
    fi
}

# Function to set up an exit handler
setup_exit_handler() {
    # Function to execute when the script closes
    cleanup() {
        log_message "Script terminating..."
        # Publish offline status
        publish_mqtt "${MQTT_BASE}/switch/${DEVICE_FORMATTED}/status" "offline" "retain"
        # Remove PID file
        if [ -f "$PID_FILE" ]; then
             rm -f "$PID_FILE"
        fi
        log_message "Script terminated"
    }
    
    # Set up trap for EXIT signal
    trap cleanup EXIT TERM INT
}

# Main function
main() {
    # Clear previous log at start
    echo "" > "$LOG_FILE"
    log_message "Script started in $([ $DEBUG_MODE -eq 1 ] && echo "DEBUG" || echo "NORMAL") mode"
    log_message "MQTT base topic: $MQTT_BASE"
    log_message "Device identifier: $DEVICE_FORMATTED"
    
    # Set up exit handler
    setup_exit_handler
    
    # Publish initial status
    publish_wifi_status
    
    # Patró de subscripció millorat per capturar correctament els missatges
    # Usem patró de nivell MQTT (+ substitueix un nivell SENCER del tòpic)
    switch_subscription="${MQTT_BASE}/switch/${DEVICE_FORMATTED}/+/set"
    button_subscription="${MQTT_BASE}/button/${DEVICE_FORMATTED}/+/set"
    
    # Subscribe to control topics and wait for messages
    mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
                  -t "$switch_subscription" -t "$button_subscription" -v | while read -r line; do
        # Utilitzem awk per dividir correctament pel primer espai
        topic=$(echo "$line" | awk '{print $1}')
        message=$(echo "$line" | awk '{$1=""; print substr($0,2)}')
        
        # Processament especial per als missatges del botó
        if echo "$topic" | grep -q "^${MQTT_BASE}/button/"; then
            if [ "$message" = "REBOOT" ]; then
                process_message "$topic" "$message"
            else
                if echo "$topic" | grep -q "${MQTT_BASE}/button/${DEVICE_FORMATTED}/"; then
                    button_id=$(echo "$topic" | sed "s|^${MQTT_BASE}/button/${DEVICE_FORMATTED}/\(${DEVICE_FORMATTED}_[^/]*\)/set|\1|")
                    publish_mqtt "${MQTT_BASE}/button/${DEVICE_FORMATTED}/${button_id}/error" "Invalid message format: $message" "retain"
                fi
            fi
        # Processament per als missatges dels interruptors WiFi
        elif echo "$topic" | grep -q "^${MQTT_BASE}/switch/"; then
            # Només processem el missatge si és vàlid (ON o OFF)
            if echo "$message" | grep -q -E "^(ON|OFF)$"; then
                process_message "$topic" "$message"
            else
                # Identifiquem el device ID per enviar l'error
                if echo "$topic" | grep -q "${MQTT_BASE}/switch/${DEVICE_FORMATTED}/"; then
                    network_id=$(echo "$topic" | sed "s|^${MQTT_BASE}/switch/${DEVICE_FORMATTED}/\(${DEVICE_FORMATTED}_[^/]*\)/set|\1|")
                    publish_mqtt "${MQTT_BASE}/switch/${DEVICE_FORMATTED}/${network_id}/error" "Invalid message format: $message" "retain"
                fi
            fi
        fi
    done
}

# Execute the main function
main "$@"
