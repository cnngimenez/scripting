#!/bin/bash

# uialert TXT
#
# Mostrar una alerta y detenerse para que el usuario pueda verla.
function uialert {
    zenity --info --text="$1" &> /dev/null
}

# uimsg TEXT
#
# Mostrar un mensaje de estado. No debe interrumpir el proceso.
function uimsg {
    # zenity --info --text="$1"
    echo
    echo "$1"
}

function addfalse {    
    for i in $(cat) ; do
        echo 'FALSE'
        echo "$i"
    done
}

# echo -e "data\ndata\n..." | uiselect TEXT
function uiselect {
    echo "${@:2}" | addfalse | zenity --list --radiolist --text="$1" --column '' --column 'Opción' 2> /dev/null
}

# uiyn TEXT
function uiyn {
    if zenity --question --text="$1" &> /dev/null; then
        echo 'y'
    else
        echo 'n'
    fi    
}

function uiprogress_start {
    zenity --progress --texl="$1" --pulsate --no-cancel &> /dev/null &
}

function uiprogress_msg {
    echo
    echo "$1"
}

function uiprogress_end {
    kill %1
}
