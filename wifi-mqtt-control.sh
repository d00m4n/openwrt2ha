#!/bin/sh

DEBUG_MODE=0
VERSION="1.0.11"
LOG_FILE="/tmp/wifi-mqtt.log"

# Mostra el títol del script
clear
# Show the title of the script
header () {
title="-| OPENWRT2HA v$VERSION |-"
cols=80  # Amplada fixa
padding=$(( (cols - ${#title}) / 2 ))
left_padding=$(printf '%*s' "$padding" | tr ' ' '-')
right_padding=$(printf '%*s' $(( cols - padding - ${#title} )) | tr ' ' '-')
printf '%s%s%s\n' "$left_padding" "$title" "$right_padding"
}


# Mostra la informació sobre el script
about() {
    local cols=80
    local version=$1
    local start_year="2024"
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
    

    # Center the title
    # local title="ABOUT OPENWRT2HA"
    # local padding=$(( (cols - ${#title}) / 2 ))
    # local centered_title=$(printf '%*s%s%*s' "$padding" "" "$title" "$padding" "")
    
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
# Comprovem si s'ha passat el paràmetre --about
if [ "$1" = "--about" ]; then
    about $VERSION
fi
# Comprovem si s'ha passat el paràmetre --debug
if [ "$1" = "--debug" ]; then
    DEBUG_MODE=1
fi

# Mostra el títol
header
# Funció per registrar missatges
log_message() {
    message="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    
    if [ $DEBUG_MODE -eq 1 ]; then
        # En mode debug, mostrem per pantalla i escrivim al fitxer
        echo "$message" | tee -a "$LOG_FILE"
    else
        # En mode normal, només escrivim al fitxer
        echo "$message" >> "$LOG_FILE"
    fi
}

# Carrega la configuració des del fitxer .env si existeix
ENV_FILE=~/openwrt2ha/.wifi-mqtt-control.env
if [ -f $ENV_FILE ]; then
  . $ENV_FILE
  log_message "Loaded env: $ENV_FILE" 	 
else
  # Configuració per defecte si no hi ha fitxer .env
  log_message "Default config"
  MQTT_HOST="localhost"
  MQTT_PORT="1883"
  MQTT_USER=""
  MQTT_PASS=""
fi
log_message "Connection host: $MQTT_HOST:$MQTT_PORT"


# Obté la descripció del dispositiu de la configuració de samba
DEVICE_DESCRIPTION=$(uci get samba4.@samba[0].description 2>/dev/null || echo "OpenWRT")
# Converteix a majúscules i elimina guions
DEVICE_FORMATTED=$(echo "$DEVICE_DESCRIPTION" | tr '[a-z]' '[A-Z]' | tr -d '-')

# Configura els temes MQTT
MQTT_BASE="homeassistant"
MQTT_DEVICE_BASE="openwrt/$DEVICE_FORMATTED"





# Funció per publicar missatges MQTT
publish_mqtt() {
    local topic=$1
    local message=$2
    local retain=$3
    
    if [ "$retain" = "retain" ]; then
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" -t "$topic" -m "$message" -r
    else
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" -t "$topic" -m "$message"
    fi
    
    log_message "Publicat a $topic: $message"
}

# Funció per configurar la descoberta de Home Assistant per a una xarxa WiFi
setup_discovery_for_network() {
    local ssid=$1
    local device=$2
    local status=$3
    
    # Formatem l'SSID per a ser utilitzat en rutes MQTT (substituïm espais i caràcters especials)
    log_message "SSID: $ssid"
    local ssid_formatted=$(echo "$ssid" | tr ' ' '_' | tr -c '[:alnum:]_' '_')
    
    # Configurem el tema de descoberta
    local discovery_topic="$MQTT_BASE/switch/${DEVICE_FORMATTED}_${ssid_formatted}/config"
    
    # Creem el payload JSON per a Home Assistant
    local discovery_payload='{
        "name": "'$ssid' WiFi",
        "state_topic": "'$MQTT_DEVICE_BASE'/wifi/networks/'$ssid'",
        "command_topic": "'$MQTT_DEVICE_BASE'/wifi/control",
        "payload_on": "'$ssid':on",
        "payload_off": "'$ssid':off",
        "state_on": "'$device':on",
        "state_off": "'$device':off",
        "availability_topic": "'$MQTT_DEVICE_BASE'/status",
        "unique_id": "'$DEVICE_FORMATTED'_'$ssid_formatted'_wifi",
        "device": {
            "identifiers": ["'$DEVICE_FORMATTED'"],
            "name": "'$DEVICE_DESCRIPTION' WiFi",
            "model": "OpenWRT WiFi Control",
            "manufacturer": "OpenWRT"
        }
    }'
    
    # Publiquem la configuració de descoberta
    publish_mqtt "$discovery_topic" "$discovery_payload" "retain"
    log_message "Configurada descoberta per a $ssid"
}

# Funció per publicar l'estat de totes les xarxes WiFi
publish_wifi_status() {
    log_message "Publicant estat de totes les xarxes WiFi..."
    
    # Publiquem l'estat de disponibilitat
    publish_mqtt "$MQTT_DEVICE_BASE/status" "online" "retain"
    
    # Obtenim totes les interfícies WiFi
    interfaces=$(uci show wireless | grep "\.ssid=" | cut -d. -f1-2)
    
    # Publiquem la llista de xarxes
    network_list=""
    
    for iface in $interfaces; do
        # Obtenim el SSID
        ssid=$(uci get ${iface}.ssid)
        # Obtenim el dispositiu ràdio
        device=$(uci get ${iface}.device)
        # Comprovem si està desactivada
        disabled=$(uci -q get ${iface}.disabled || echo "0")
        
        # Determinem l'estat
        if [ "$disabled" = "1" ]; then
            status="off"
        else
            status="on"
        fi
        
        # Afegim a la llista
        if [ -z "$network_list" ]; then
            network_list="${ssid}:${device}:${status}"
        else
            network_list="${network_list},${ssid}:${device}:${status}"
        fi
        
        # Publiquem l'estat d'aquesta xarxa
        publish_mqtt "$MQTT_DEVICE_BASE/wifi/networks/${ssid}" "${device}:${status}" "retain"
        
        # Configurem la descoberta per a aquesta xarxa WiFi
        setup_discovery_for_network "$ssid" "$device" "$status"
        
        log_message "WiFi $ssid ($device) està $status"
    done
    
    # Publiquem la llista completa
    publish_mqtt "$MQTT_DEVICE_BASE/wifi/list" "$network_list" "retain"
}

# Funció per gestionar els missatges rebuts
process_message() {
    topic="$1"
    message="$2"
    
    log_message "Rebut missatge: $topic -> $message"
    
    # Si el tema és de control
    if echo "$topic" | grep -q "^$MQTT_DEVICE_BASE/wifi/control"; then
        # Dividir el missatge en SSID i acció
        ssid=$(echo "$message" | cut -d':' -f1)
        action=$(echo "$message" | cut -d':' -f2)
        
        log_message "SSID: $ssid, Acció: $action"
        
        # Trobem la interfície basada en el SSID
        iface=$(uci show wireless | grep "\.ssid='$ssid'" | cut -d. -f1-2)
        
        if [ -z "$iface" ]; then
            log_message "No s'ha trobat cap interfície amb SSID $ssid"
            publish_mqtt "$MQTT_DEVICE_BASE/wifi/error" "SSID no trobat: $ssid"
            return
        fi
        
        # Obtenim el dispositiu ràdio
        device=$(uci get ${iface}.device)
        log_message "Dispositiu ràdio: $device"
        
        case "$action" in
            "on"|"ON")
                # Habilitar aquesta xarxa WiFi específica
                log_message "Habilitant WiFi $ssid"
                uci set ${iface}.disabled='0'
                uci commit wireless
                
                # Apliquem els canvis reiniciant específicament aquest ràdio
                log_message "Aplicant canvis al dispositiu $device"
                wifi up $device
                
                log_message "WiFi $ssid habilitat"
                sleep 2  # Esperem que s'apliquin els canvis
                publish_wifi_status
                ;;
            "off"|"OFF")
                # Desactivar aquesta xarxa WiFi específica
                log_message "Desactivant WiFi $ssid"
                uci set ${iface}.disabled='1'
                uci commit wireless
                
                # Apliquem els canvis reiniciant específicament aquest ràdio
                log_message "Aplicant canvis al dispositiu $device"
                wifi up $device  # Reiniciem el ràdio amb la nova configuració
                
                log_message "WiFi $ssid desactivat"
                sleep 2  # Esperem que s'apliquin els canvis
                publish_wifi_status
                ;;
            "status")
                # No fem res, ja que la funció publish_wifi_status s'encarregarà
                log_message "Sol·licitud d'estat rebuda"
                publish_wifi_status
                ;;
            *)
                log_message "Acció desconeguda: $action"
                publish_mqtt "$MQTT_DEVICE_BASE/wifi/error" "Acció desconeguda: $action"
                ;;
        esac
    fi
}

# Funció per configurar un exit handler
setup_exit_handler() {
    # Funció per executar quan l'script es tanca
    cleanup() {
        log_message "Script finalitzant..."
        # Publiquem l'estat offline
        publish_mqtt "$MQTT_DEVICE_BASE/status" "offline" "retain"
        log_message "Script finalitzat"
    }
    
    # Configurem el trap per a la senyal EXIT
    trap cleanup EXIT
}

# Funció principal
main() {
    # Netejar el log anterior al inici
    echo "" > "$LOG_FILE"
    log_message "Script iniciat en mode $([ $DEBUG_MODE -eq 1 ] && echo "DEBUG" || echo "NORMAL")"
    log_message "Utilitzant tema MQTT: $MQTT_DEVICE_BASE (derivat de '$DEVICE_DESCRIPTION')"
    
    # Configurem el gestor de sortida
    setup_exit_handler
    
    # Publiquem l'estat inicial
    publish_wifi_status
    
    log_message "Esperant missatges MQTT a $MQTT_DEVICE_BASE/wifi/control..."
    
    # Ens subscrivim al tema de control i esperem missatges
    mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" -t "$MQTT_DEVICE_BASE/wifi/control" -v | while read -r line; do
        topic=$(echo "$line" | cut -d' ' -f1)
        message=$(echo "$line" | cut -d' ' -f2-)
        
        process_message "$topic" "$message"
    done
}

# Executar la funció principal
main "$@"
