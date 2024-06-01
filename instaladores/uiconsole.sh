#!/bin/bash

function uialert {
    echo
    echo "$1"
}

function uimsg {
    echo
    echo "$1"
}

function uiselect {    
    echo "$1"
    resp=''
    while [[ -z "$resp" ]]; do
        select resp in ${@:2}; do
            echo "$resp"
            break;
        done
    done
}

function uiyn {
    resp=''
    while [[ -z "$resp" ]]; do
        echo "$1"
        echo '(SI/no)'

        read resp
        case "$resp" in
            'SI') echo 'y';;
            'NO') echo 'n';;
            'no') echo 'n';;
            *) resp='';;
        esac
    done
}

function uiprogress_start {
    echo
}

function uiprogress_msg {
    echo
    echo "$1"
}

function uiprogress_end {
    echo
}
