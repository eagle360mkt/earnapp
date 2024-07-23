#!/usr/bin/env bash
# LICENSE_CODE ZON ISC

PRODUCT=$2

# Atualize o caminho de configuração para o diretório do usuário
LCONF="$HOME/.earnapp/ver_conf.json"

if [[ -z "$PRODUCT" ]]; then
  if [[ -f "$LCONF" ]]; then
    if (grep appid < "$LCONF" | grep "piggy" > /dev/null); then
      PRODUCT="piggybox"
    fi
  fi
fi

if [[ -z "$PRODUCT" ]]; then
  PRODUCT="earnapp"
fi

VERSION="1.468.70"
PRINT_PERR=0
PRINT_PERR_DATA=0
OS_NAME=$(uname -s)
OS_ARCH=$(uname -m)
PERR_ARCH=$(uname -m| tr '[:upper:]' '[:lower:]'| tr -d -c '[:alnum:]_')
OS_VER=$(uname -v)
APP_VER=$(earnapp --version 2>/dev/null)
VER="${APP_VER:-none}"
USER=$(whoami)
RHOST=$(hostname)
_LADDR=$(hostname -I | cut -d' ' -f1)
LADDR=${_LADDR:-unknown}
IP=$(curl -q4 ifconfig.co 2>/dev/null)
IP=${_IP:-unknown}
NETWORK_RETRY=3

# Atualize o caminho de log para o diretório do usuário
LOG_DIR="$HOME/.earnapp"
mkdir -p "$LOG_DIR"

SERIAL="unknown"
SFILE="/sys/firmware/devicetree/base/serial-number"
if [ -f $SFILE ]; then
    SERIAL=$(sha1sum < "$SFILE" | awk '{print $1}')
fi

AUTO=0
if [[ $0 == '-y' ]] || [[ $1 == '-y' ]]; then
    AUTO=1
fi

RID=$(LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1)
UUID=$(cat "$HOME/.earnapp/uuid" 2>/dev/null)
UUID_HASH=$(md5sum <<< "$UUID")
UUID_I=$((0x${UUID_HASH%% *}))
UUID_N=$((${UUID_I#-}%100))
INSTALL=0

RS=""
PERR_URL="https://perr.brightdata.com/client_cgi/perr"

is_cmd_defined() {
    local cmd=$1
    type -P "$cmd" > /dev/null
    return $?
}

escape_json() {
    local strip_nl=${1//$'\n'/\\n}
    local strip_tabs=${strip_nl//$'\t'/\ }
    local strip_quotes=${strip_tabs//$'"'/\ }
    RS=$strip_quotes
}

LOG=""
LOG_FILENAME=""
read_log() {
    if [ -f "$LOG_FILENAME" ]; then
       LOG=$(tail -50 "$LOG_FILENAME") # | tr -dc '[:print:]')
    fi
}

print() {
    STR=$1
    if [ $AUTO = 1 ]; then
        STR="$(date -u +'%F %T') $STR"
    fi
    echo "$STR"
}

perr() {
    local name=$1
    local note="$2"
    local filehead="$3"
    local ts
    ts=$(date +"%s")
    local ret=0
    escape_json "$note"
    local note=$RS
    escape_json "$filehead"
    local filehead=$RS
    local url_glob="${PERR_URL}/?id=earnapp_cli_sh_${name}"
    local url_arch="${PERR_URL}/?id=earnapp_cli_sh_${PERR_ARCH}_${name}"
    local build="Version: $VERSION\nOS Version: $OS_VER\nCPU ABI: $OS_ARCH\nProduct: $PRODUCT\nInstall ID: $RID\nPublic IP: $IP\nLocal IP: $LADDR"
    local data="{
        \"uuid\": \"$UUID\",
        \"client_ts\": \"$ts\",
        \"ver\": \"$VER\",
        \"filehead\": \"$filehead\",
        \"build\": \"$build\",
        \"info\": \"$note\"
    }"
    if ((PRINT_PERR)); then
        if ((PRINT_PERR_DATA)); then
            print "📧 $url_glob $data"
        else
            print "📧 $url_glob $note"
        fi
    fi
    for ((i=0; i<NETWORK_RETRY; i++)); do
        if is_cmd_defined "curl"; then
            curl -s -X POST "$url_glob" --data "$data" \
                -H "Content-Type: application/json" > /dev/null
            curl -s -X POST "$url_arch" --data "$data" \
                -H "Content-Type: application/json" > /dev/null
        elif is_cmd_defined "wget"; then
            wget -S --header "Content-Type: application/json" \
                 -O /dev/null -o /dev/null --post-data="$data" \
                 --quiet "$url_glob" > /dev/null
            wget -S --header "Content-Type: application/json" \
                 -O /dev/null -o /dev/null --post-data="$data" \
                 --quiet "$url_arch" > /dev/null
        else
            print "⚠ No transport to send perr"
        fi
        ret=$?
        if ((!ret)); then break; fi
    done
}

welcome_text() {
    echo "Installing EarnApp CLI"
    echo "Welcome to EarnApp for Linux and Raspberry Pi."
    echo "EarnApp makes you money by sharing your spare bandwidth."
    echo "You will need your EarnApp account username/password."
    echo "Visit earnapp.com to sign up if you don't have an account yet"
    echo
    echo "To use EarnApp, allow BrightData to occasionally access websites \
through your device. BrightData will only access public Internet web \
pages, not slow down your device or Internet and never access personal \
information, except IP address - see privacy policy and full terms of \
service on earnapp.com."
}

ask_consent() {
    read -rp "Do you agree to EarnApp's terms? (Write 'yes' to continue): " consent
}

# Remova a verificação de root, pois você está executando sem sudo
# if [[ $EUID -ne 0 ]]; then
#   print "⚠ This script must be run as root"
#   exit 1
# fi

if [[ "$VER" == "$VERSION" ]]; then
   perr "00_same_ver"
   print "✔ The application of the same version is already installed"
   LOG_FILENAME="$LOG_DIR/earnapp_services_restart.log"
   {
       # Modifique para não usar 'service' se não estiver disponível
       echo "Restarting and checking services..."
       # Adicione os comandos para reiniciar serviços locais se possível
   } >> "$LOG_FILENAME"
   read_log
   perr "00_services_restart" "$VER" "$LOG"
   exit 0
fi

LOG_FILENAME="$LOG_DIR/cleanup.log"
find /tmp -name "earnapp_*" | grep -v $VERSION > "$LOG_FILENAME"
echo "$CLEANUP_CMD"
if [ -s $LOG_FILENAME ]; then
    print "✔ Cleaning up..."
    xargs rm -f < "$LOG_FILENAME"
    read_log
    perr "00_cleanup" "$VER" "$LOG"
fi

# 200MB
FREE_SPACE_MIN=$((2*100*1024*1024))
FREE_SPACE_BLOCKS=$(df --total | grep total | awk '{print $2}')
FREE_SPACE_BYTES=$((FREE_SPACE_BLOCKS*1000))
FREE_SPACE_PRETTY=$(numfmt --to iec --format "%8.4f" "$FREE_SPACE_BYTES" | awk '{print $1}')

echo "✔ Checking prerequisites..."
if ((FREE_SPACE_BYTES < FREE_SPACE_MIN)); then
    FREE_SPACE_MIN_PRETTY=$(numfmt --to iec --format "%8.4f" "$FREE_SPACE_MIN" | awk '{print $1}')
    perr "00_disk_full" "$FREE_SPACE_PRETTY/$FREE_SPACE_MIN_PRETTY"
    FREE_SPACE_DIFF=$((FREE_SPACE_MIN-FREE_SPACE_BYTES))
    FREE_SPACE_DIFF_PRETTY=$(numfmt --to iec --format "%8.4f" "$FREE_SPACE_DIFF" | awk '{print $1}')
    echo "⚠ Not enough space to install."
    echo "⚠ Please free up at least $FREE_SPACE_DIFF_PRETTY and try again."
    exit 1
fi

if ((INSTALL)); then
    perr "00_sh_install" "$VERSION" "$UUID_N"
fi

perr "01_start" "$VERSION" "available: $
