#!/bin/bash

## Variables
INSTALL_LOG="/tmp/v1es_install.log"
## Pre-Check
# Check whether /tmp is writable
if [[ ! -w /tmp ]]; then
    echo "[ERROR] /tmp is not writable. Please check the permission of /tmp."
    exit 1
fi

# Check whether the script is running as root
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "[ERROR] You are not running as the root user.  Please try again with root privileges."
    echo "$(date) [ERROR] You are not running as the root user.  Please try again with root privileges." >> $INSTALL_LOG
    exit 1
fi

# Check whether curl is installed
if ! type curl >/dev/null 2>&1; then
    echo "[ERROR] Please install curl before running this script."
    echo "$(date) [ERROR] Please install curl before running this script." >> $INSTALL_LOG
    exit 1
fi

# Check whether curl supports tls v1.2
CURL_TLS_VERSION=$(curl --help tls | grep tlsv1.2)
if [[ -z "$CURL_TLS_VERSION" ]]; then
    echo "[ERROR] Your version of curl does not support TLS v1.2. Please update curl."
    echo "$(date) [ERROR] Your version of curl does not support TLS v1.2. Please update curl." >> $INSTALL_LOG
    exit 1
fi
echo "[INFO] curl support tls v1.2."
echo "$(date) [INFO] curl support tls v1.2." >> $INSTALL_LOG

# Check whether tar is installed
if ! type tar >/dev/null 2>&1; then
    echo "[ERROR] Please install tar before running this script."
    echo "$(date) [ERROR] Please install tar before running this script." >> $INSTALL_LOG
    exit 1
fi

# check if base64 method exists
if ! type base64 >/dev/null 2>&1; then
    echo "[ERROR] Please install base64 before running this script."
    echo "$(date) [ERROR] Please install base64 before running this script." >> $INSTALL_LOG
    exit 1
fi

echo "[INFO] Start deploying."
echo "$(date) [INFO] Start deploying." >> $INSTALL_LOG
# PROXY_ADDR_PORT and PROXY_CREDENTIAL define proxy for software download and agent activation
PROXY_ADDR_PORT="" 
PROXY_USERNAME=""
PROXY_PASSWORD=""

# HTTP_PROXY is exported for compatibility purpose, remove it if it is not needed in your environment
PROXY_CREDENTIAL=""
if [[ ! -z $PROXY_PASSWORD ]]; then
    PROXY_CREDENTIAL=$(eval echo \"$PROXY_USERNAME:$PROXY_PASSWORD\")
elif [[ ! -z $PROXY_USERNAME ]]; then
    PROXY_CREDENTIAL=$(eval echo "$PROXY_USERNAME")
fi

if [[ ! -z $PROXY_CREDENTIAL ]]; then
    export HTTP_PROXY=http://$PROXY_CREDENTIAL@$PROXY_ADDR_PORT/
    export HTTPS_PROXY=http://$PROXY_CREDENTIAL@$PROXY_ADDR_PORT/
    echo "[INFO] Use proxy with credentials."
    echo "$(date) [INFO] Use proxy with credentials." >> $INSTALL_LOG
elif [[ ! -z $PROXY_ADDR_PORT ]]; then
    export HTTP_PROXY=http://$PROXY_ADDR_PORT/
    export HTTPS_PROXY=http://$PROXY_ADDR_PORT/
    echo "[INFO] Use proxy without credentials."
    echo "$(date) [INFO] Use proxy without credentials." >> $INSTALL_LOG
fi

# configure connection methods
CONNECT_CONFIG=$(eval echo -n '{\"fps\":[{\"connections\": [{\"type\": \"DIRECT_CONNECT\"}]}]}' | base64 -w 0)
if [[ $PROXY_ADDR_PORT ]]; then
    PROXY_CONFIG=$(echo "$PROXY_ADDR_PORT")
    if [[ $PROXY_USERNAME ]]; then
        CREDENTIAL_ENCODE=$(eval echo -n \"$PROXY_USERNAME:\" | base64 -w 0)
        PROXY_CONFIG=$(echo "$CREDENTIAL_ENCODE@$PROXY_ADDR_PORT")
        if [[ $PROXY_PASSWORD ]]; then
            CREDENTIAL_ENCODE=$(eval echo -n \"$PROXY_USERNAME:$PROXY_PASSWORD\" | base64 -w 0)
            PROXY_CONFIG=$(echo "$CREDENTIAL_ENCODE@$PROXY_ADDR_PORT")
        fi
    fi
    CONNECT_CONFIG=$(eval echo -n '{\"fps\":[{\"connections\": [{\"type\": \"USER_INPUT\"}]}]}' | base64 -w 0)
fi
# Platform detection
isRPM=""
linuxPlatform=""
archType=""
CURLOPTIONS="--silent --tlsv1.2"
CUSTOMER_ID="3f9da854-7b41-4742-8f28-bb2e3c7b4187"
XBC_FQDN="api-us1.xbc.trendmicro.com"

PLATFORM_DETECTION_URL="https://$XBC_FQDN/apk/platform-detection-script"
CURLOUT=$(eval curl -w "%{http_code}" -L -H \"X-Customer-Id: $CUSTOMER_ID\" -o /tmp/PlatformDetection $CURLOPTIONS $PLATFORM_DETECTION_URL;)

err=$?
if [[ $err -eq 60 ]]; then
    echo "[ERROR] TLS certificate validation for the platform detection script download has failed. Please check that your TLS certificate is signed by a trusted root certificate authority."
    echo "$(date) [ERROR] TLS certificate validation for the platform detection script download has failed. Please check that your TLS certificate is signed by a trusted root certificate authority." >> $INSTALL_LOG
    exit 1;
fi

if [[ $CURLOUT -ne 200 || $err -ne 0 ]]; then
    echo "[ERROR] Failed to download the platform detection script. Curl error: $err, HTTP error: $CURLOUT."
    echo "$(date) [ERROR] Failed to download the platform detection script. Curl error: $err, HTTP error: $CURLOUT." >> $INSTALL_LOG
    exit 1
fi

if [[ -s /tmp/PlatformDetection ]]; then
    . /tmp/PlatformDetection
else
    echo "[ERROR] Failed to download the agent platform detection script."
    echo "$(date) [ERROR] Failed to download the agent platform detection script." >> $INSTALL_LOG
    exit 1
fi

platform_detect
if [[ -z "${linuxPlatform}" ]] || [[ -z "${isRPM}" ]]; then
    echo "[ERROR] ${detectError}"
    echo "$(date) [ERROR] ${detectError}." >> $INSTALL_LOG
    exit 1
fi
## Get Installer Package
INSTALLER_PATH="/tmp/v1es_installer.tgz"

# Get XBC installer
GET_INSTALLER_URL="https://$XBC_FQDN/apk/installer"
HTTP_BODY=""

if [[ ${archType} == "x86_64" ]]; then
    HTTP_BODY='{"company_id":"3f9da854-7b41-4742-8f28-bb2e3c7b4187","platform":"linux64","scenario_ids":["54c1def0-b89d-4b80-8e42-1f9d38a565b0"]}'
elif [[ ${archType} == "aarch64" ]]; then
    HTTP_BODY='{"company_id":"3f9da854-7b41-4742-8f28-bb2e3c7b4187","platform":"linuxaarch64","scenario_ids":["22d2d438-bdb5-4b4e-bcc0-f0aaa6916c6f"]}'
elif [[ ${archType} == "ppc64le" ]]; then
    HTTP_BODY='{"company_id":"3f9da854-7b41-4742-8f28-bb2e3c7b4187","platform":"linuxppc64le","scenario_ids":["b6e8bc44-3510-4f75-b562-2b1a1f0b302c"]}'
else
    echo "[ERROR] Architecture type ${archType} is not in the supported architecture list."
    echo "$(date) [ERROR] Architecture type ${archType} is not in the supported architecture list." >> $INSTALL_LOG
    exit 1
fi

echo "[INFO] Start downloading the installer."
echo "$(date) [INFO] Start downloading the installer." >> $INSTALL_LOG
CURLOUT=$(eval curl -w "%{http_code}" -L -H \"Content-Type: application/json\" -H \"X-Customer-Id: $CUSTOMER_ID\" -d \'$HTTP_BODY\' -o $INSTALLER_PATH $CURLOPTIONS $GET_INSTALLER_URL;)
err=$?
if [[ $CURLOUT -ge 400 || $err -ne 0 ]]; then
    echo "[ERROR] Failed to download the installer. Curl error: $err, HTTP error: $CURLOUT."
    echo "$(date) [ERROR] Failed to download the installer. Curl error: $err, HTTP error: $CURLOUT." >> $INSTALL_LOG
    exit 1
fi
echo "[INFO] The installer downloaded."
echo "$(date) [INFO] The installer downloaded." >> $INSTALL_LOG
TAR_ARGS="-zxvf"
## Install v1es agents
EXTRATED_DIR="/tmp/v1es"
mkdir -p $EXTRATED_DIR && tar $TAR_ARGS $INSTALLER_PATH -C $EXTRATED_DIR
err=$?
if [[ $err -ne 0 ]]; then
    echo "[ERROR] Fail to extract the agent installer / full package. Error: $err."
    echo "$(date) [ERROR] Fail to extract the agent installer / full package. Error: $err." >> $INSTALL_LOG
    exit 1
fi
# set xbc site and scenario IDs
XBC_ENV="prod-us1"
if [[ ${archType} == "x86_64" ]]; then
    PROPERTY=$(eval echo '{\"xbc_env\": \"$XBC_ENV\", \"xbc_agent_token\": "\"54c1def0-b89d-4b80-8e42-1f9d38a565b0\"", \"full_package\": true}')
elif [[ ${archType} == "aarch64" ]]; then
    PROPERTY=$(eval echo '{\"xbc_env\": \"$XBC_ENV\", \"xbc_agent_token\": "\"22d2d438-bdb5-4b4e-bcc0-f0aaa6916c6f\"", \"full_package\": true}')
elif [[ ${archType} == "ppc64le" ]]; then
    PROPERTY=$(eval echo '{\"xbc_env\": \"$XBC_ENV\", \"xbc_agent_token\": "\"b6e8bc44-3510-4f75-b562-2b1a1f0b302c\"", \"full_package\": true}')
fi
echo $PROPERTY > $EXTRATED_DIR/.property
echo "[INFO] Start agent installation"
echo "$(date) [INFO] Start agent installation" >> $INSTALL_LOG



echo "[INFO] Agent is installing..."
echo "$(date) [INFO] Agent is installing..." >> $INSTALL_LOG

FQDN_ARG=''
GROUP_ID_ARG=''
if [[ $PROXY_CONFIG ]]; then
    echo "[INFO] The agent installation is using a proxy."
    echo "$(date) [INFO] The agent installation is using a proxy." >> $INSTALL_LOG
    INSTALL_RESULT=$(eval $EXTRATED_DIR/tmxbc install --proxiesWithCred \'$PROXY_CONFIG\' --connection \'$CONNECT_CONFIG\' $FQDN_ARG $GROUP_ID_ARG)
else
    echo "[INFO] The agent installation is using a direct connection."
    echo "$(date) [INFO] The agent installation is using a direct connection." >> $INSTALL_LOG
    INSTALL_RESULT=$(eval $EXTRATED_DIR/tmxbc install --connection \'$CONNECT_CONFIG\' $FQDN_ARG $GROUP_ID_ARG)
fi

# check if XBC is installed as usual
if [[ $? -ne 0 ]]; then
    echo "[ERROR] Failed to install agent. Error: $INSTALL_RESULT."
    echo "$(date) [ERROR] Failed to install agent. Error: $INSTALL_RESULT." >> $INSTALL_LOG
    exit 1
fi
echo "[INFO] Agent is installed."
echo "$(date) [INFO] Agent is installed." >> $INSTALL_LOG
# check if XBC is registered
IDENTITY_FILE_PATH="/opt/TrendMicro/EndpointBasecamp/etc/.identity"
retryCount=0
maxRetryCount=30
while [[ ! -e $IDENTITY_FILE_PATH ]]; do
    echo "[INFO] Waiting for agent to register."
    echo "$(date) [INFO] Waiting for agent to register." >> $INSTALL_LOG
    sleep 10
    retryCount=$((retryCount + 1))
    if [[ $retryCount -gt maxRetryCount ]]; then
        echo "[ERROR] Failed to register agent to the backend service. Please see the tmxbc.log for more details."
        echo "$(date) [ERROR] Failed to register agent to the backend service. Please see the tmxbc.log for more details." >> $INSTALL_LOG
        exit 1
    fi
done
echo "[INFO] Agent is registered."
echo "$(date) [INFO] Agent is registered." >> $INSTALL_LOG
echo "[INFO] Finish deploying."
echo "$(date) [INFO] Finish deploying." >> $INSTALL_LOG
exit 0
