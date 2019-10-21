#!/bin/bash
_SCRIPT_LOCATION="$(cd "$(dirname ${BASH_SOURCE[0]})"; pwd -P)"

source "${_SCRIPT_LOCATION}/formatting.sh"

function log {
    _icon="${1}"
    _msg="${2}"
    _color="${3}"
    echo -e "${_color}${_icon} ${_msg}${COLOR_NONE}"
}

function logWithTimestamp {
    _icon=$1
    _msg=$2
    echo -e "$(date +'%F %T') $1 $2"
}

function logInternal {
    if [ ! -z $ST_INTERNAL ]; then
        log " ^ " "${1}" ${COLOR_DGRAY}
    fi
}
function logVerbose { log "   " "${1}" "${COLOR_DGRAY}"; }
function logDebug { log " * " "${1}" ${COLOR_LBLUE}; }
function logProcess { log "..." "${1}" ${COLOR_LGRAY}; }
function logBlank { log "   " "${1}" "${2,-$COLOR_NONE}"; }
function logInfo { log "[i]" "${1}" ${COLOR_GREEN}; }
function logWarn { log "[!]" "${1}" ${COLOR_YELLOW}; }
function logError { log "/!\\" "${1}" ${COLOR_LRED}; }
function logFatal { >&2 log "!!!" "${1}" ${COLOR_RED}; }

function echoErr { >&2 echo $1; }

logInternal "Included logging"
