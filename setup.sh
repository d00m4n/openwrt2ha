#!/bin/sh
VERSION="1.0.18"
# Setup script for OpenWrt2HA
# This script installs the program as a service that starts automatically

# Define constants
SCRIPT_NAME="openwrt2ha.sh"
SCRIPT_PATH="/usr/bin/openwrt2ha"
SERVICE_NAME="openwrt2ha"
SCRIPT_SOURCE="$(pwd)/${SCRIPT_NAME}"
INITD_SCRIPT_PATH="$(pwd)/init.script"
CONFIG_DIR="/etc/openwrt2ha"
ENV_FILE=".${SERVICE_NAME}.env"
INITD_PATH="/etc/init.d/${SERVICE_NAME}"
LOG_PATH="/var/log/${SERVICE_NAME}"
log_message "Creating ${LOG_PATH}..."
mkdir -p "${LOG_PATH}"



# Function to display messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}
log_message "OpenWrt2HA Setup Script v${VERSION}"

# Check if the original script exists
if [ ! -f "${SCRIPT_SOURCE}" ]; then
    log_message "Error: ${SCRIPT_NAME} script not found in the current directory."
    log_message "Please run this script from the same directory where ${SCRIPT_NAME} is located."
    exit 1
fi

# Create directory structure
log_message "Creating directory structure..."
log_message "Creating ${SCRIPT_PATH}..."
mkdir -p "${SCRIPT_PATH}"
log_message "Creating ${CONFIG_DIR}..."
mkdir -p "${CONFIG_DIR}"

# Copy the script to the destination location
log_message "Copying script to ${SCRIPT_PATH}/${SCRIPT_NAME}..."
cp "${SCRIPT_SOURCE}" "${SCRIPT_PATH}/${SCRIPT_NAME}"
chmod +x "${SCRIPT_PATH}/${SCRIPT_NAME}"


# Check if an environment file already exists
if [ -f "${CONFIG_DIR}/${ENV_FILE}" ]; then
    log_message "${CONFIG_DIR}/${ENV_FILE} found."
else
    log_message "${CONFIG_DIR}/${ENV_FILE} not found."
    read -r -p "Create a new configuration file? (y/n)" response
    if [ "$response" = "y" ]; then
        read -r -p "MQTT host[localhost]: " hostname
        hostname=${hostname:-localhost}
        read -r -p "MQTT port[1883]: " port
        port=${port:-1883}
        read -r -p "MQTT user: " user
        read -r -s -p "MQTT password: " password
        echo ""
        read -r -p "HA name: " ha_name
        cat > "${CONFIG_DIR}/${ENV_FILE}" << EOF
# MQTT Server Configuration
MQTT_HOST="${hostname}"
MQTT_PORT="${port}"
MQTT_USER="${user}"
MQTT_PASS="${password}"
HA_NAME="${ha_name}"
EOF
        log_message "Configuration file created at ${CONFIG_DIR}/${ENV_FILE}"
        EXIT 0

        # cat > "${CONFIG_DIR}/${ENV_FILE}" << EOF
    else 
        log_message "Please create a configuration file at ${CONFIG_DIR}/${ENV_FILE}."
        exit 1
    fi
fi

# Create init.d script
log_message "Creating init.d script..."
# cp "${INITD_SCRIPT_PATH}" "${INITD_PATH}"
cat > "${INITD_PATH}" << EOF
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1
PROG="${SERVICE_NAME}"
SCRIPT="${SCRIPT_PATH}/${SCRIPT_NAME}"
PID_FILE="/var/run/${SERVICE_NAME}.pid"

start_service() {
    procd_open_instance
    procd_set_param command \$SCRIPT
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn
    procd_set_param pidfile \$PID_FILE
    procd_close_instance
    log_message "Service ${SERVICE_NAME} started"
}

stop_service() {
    service_stop \$SCRIPT
    # També assegurem-nos que eliminem el PID file si existeix
    [ -f \$PID_FILE ] && rm -f \$PID_FILE
    log_message "Service ${SERVICE_NAME} stopped"
}

reload_service() {
    # La funció de reload si només volem recarregar la configuració sense reiniciar
    log_message "Reloading service ${SERVICE_NAME}..."
    stop_service
    start_service
}

service_triggers() {
    # Aquesta funció permet que el servei es reiniciï automàticament 
    # quan canvien certs fitxers o configuracions
    procd_add_reload_trigger "${CONFIG_DIR}/${ENV_FILE}"
}

boot() {
    # Aquesta funció és cridada durant l'arrencada del sistema
    start_service
}

# Function to log messages
log_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> /var/log/${SERVICE_NAME}/${SERVICE_NAME}.log
}
EOF

# Make init.d script executable
chmod +x "${INITD_PATH}"

# Enable and start the service
log_message "Enabling and starting the service..."
/etc/init.d/${SERVICE_NAME} enable
/etc/init.d/${SERVICE_NAME} start

# Verify that the service has started
if pgrep -f "${SCRIPT_PATH}/${SCRIPT_NAME}" > /dev/null; then
    log_message "The ${SERVICE_NAME} service has been installed and started successfully."
    log_message "You can edit the configuration at: ${CONFIG_DIR}/${ENV_FILE}"
    log_message "To restart the service: /etc/init.d/${SERVICE_NAME} restart"
    log_message "To stop the service: /etc/init.d/${SERVICE_NAME} stop"
    log_message "To check status: pgrep -f ${SCRIPT_NAME}"
else
    log_message "The service has been installed but does not appear to have started correctly."
    log_message "Check the logs for more information."
fi

# List installations
log_message "Installation summary:"
log_message "- Main script: ${SCRIPT_PATH}/${SCRIPT_NAME}"
log_message "- Configuration file: ${CONFIG_DIR}/${ENV_FILE}"
log_message "- Startup script: ${INITD_PATH}"

log_message "Installation completed!"