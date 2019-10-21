#!/bin/bash
if [ -t 0 ] ; then
  export SCREEN_SIZE=$(stty size)
else
  export SCREEN_SIZE="24 80"
fi
printf -v rows '%d' "${SCREEN_SIZE%% *}"
printf -v columns '%d' "${SCREEN_SIZE##* }"

r=$(( rows / 2 ))
c=$(( columns / 2 ))

#r=$(( r < 20 ? 20 : r ))
#c=$(( c < 70 ? 70 : c ))

export SCREEN_ROWS=$r
export SCREEN_COLS=$c
