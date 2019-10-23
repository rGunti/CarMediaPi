#!/bin/bash
_SCRIPT_LOCATION="$(cd "$(dirname ${BASH_SOURCE[0]})"; pwd -P)"

source "${_SCRIPT_LOCATION}/logging.sh"

function confirm {
    question=${1}
    question=$(log "[?]" "${question} ${COLOR_NONE}(Y/N) " "${COLOR_LBLUE}")

    while true; do
        read -n1 -p "${question}" yn

        case $yn in
            [Yy]*)
                echo -e "\b${COLOR_GREEN}Yes${COLOR_NONE}"
                return 0
                ;;
            [Nn]*)
                echo -e "\b${COLOR_RED}No${COLOR_NONE}"
                return 1
                ;;
            *)
                echo -e "\b${COLOR_DGRAY}Please press Y or N${COLOR_NONE}"
                ;;
        esac
    done
}
