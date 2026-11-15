#!/usr/bin/env bash

set -o pipefail
export LC_ALL=C
program=${0##*/}

error() {
    printf '%s: %s\n' "$program" "$*" >&2
}

show_help() {
    if ! cat 2>/dev/null <<'HELP'
Usage: system_info.sh [OPTIONS]
  -u, --users          List users and home directories, sorted by user name.
  -p, --processes      List running processes, sorted by PID.
  -h, --help           Show help and exit.
  -l, --log PATH       Write standard output to PATH, replacing its contents.
  -e, --errors PATH    Write standard errors to PATH, replacing its contents.

Actions may be combined. Paths containing spaces must be quoted.
Examples:
  ./system_info.sh --users
  ./system_info.sh -u -p --log output.txt --errors errors.txt
HELP
    then
        error 'Cannot write help.'
        return 1
    fi
}

show_users() {
    local users
    if ! users=$(getent passwd 2>/dev/null); then
        error 'Cannot read the user database.'
        return 1
    fi
    if ! {
        printf 'USER\tHOME\n'
        printf '%s\n' "$users" |
            sort -t: -k1,1 |
            cut -d: -f1,6 --output-delimiter=$'\t'
    } 2>/dev/null; then
        error 'Cannot format the user list.'
        return 1
    fi
}

show_processes() {
    if ! ps -eo pid,comm --sort=pid 2>/dev/null; then
        error 'Cannot read the process list.'
        return 1
    fi
}

check_output_path() {
    local path=$1 parent
    if [[ -z $path ]]; then
        error 'An output path must not be empty.'
        return 1
    fi
    if [[ -d $path ]]; then
        error "Path is a directory: $path"
        return 1
    fi
    if [[ -e $path ]]; then
        if [[ ! -w $path ]]; then
            error "File is not writable: $path"
            return 1
        fi
    else
        if ! parent=$(dirname -- "$path" 2>/dev/null); then
            error "Cannot determine the parent directory: $path"
            return 1
        fi
        if [[ ! -d $parent || ! -w $parent || ! -x $parent ]]; then
            error "Parent directory is not writable or accessible: $parent"
            return 1
        fi
    fi
}

set_errors() {
    local path=$1
    check_output_path "$path" || return 1
    if ! { exec 3>"$path"; } 2>/dev/null; then
        error "Cannot open the error file: $path"
        return 1
    fi
    exec 2>&3 3>&-
}

set_log() {
    local path=$1
    check_output_path "$path" || return 1
    if ! { exec 3>"$path"; } 2>/dev/null; then
        error "Cannot open the output file: $path"
        return 1
    fi
    exec 1>&3 3>&-
}

main() {
    local parsed parse_status=0 help=0 log_set=0 errors_set=0
    local log_path='' errors_path='' status=0 action
    local -a actions=()

    if ! command -v getopt >/dev/null 2>&1; then
        error 'GNU getopt is required.'
        return 127
    fi
    parsed=$(getopt -q --name "$program" --options upl:e:h \
        --longoptions users,processes,log:,errors:,help -- "$@") || parse_status=$?
    eval "set -- $parsed"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--users) actions+=(users); shift ;;
            -p|--processes) actions+=(processes); shift ;;
            -h|--help) help=1; shift ;;
            -l|--log) log_set=1; log_path=$2; shift 2 ;;
            -e|--errors) errors_set=1; errors_path=$2; shift 2 ;;
            --) shift; break ;;
        esac
    done

    if (( errors_set )); then
        set_errors "$errors_path" || return 1
    fi
    if (( parse_status != 0 )); then
        error 'Invalid option or missing option argument. Use --help.'
        return 2
    fi
    if (( $# != 0 )); then
        error "Unexpected argument: $1. Use --help."
        return 2
    fi
    if (( log_set )); then
        if (( errors_set )) && [[ $log_path -ef $errors_path ]]; then
            exec 1>&2
        else
            set_log "$log_path" || return 1
        fi
    fi
    if (( help )); then
        show_help
        return $?
    fi
    if (( ${#actions[@]} == 0 )); then
        error 'No action selected. Use --users, --processes or --help.'
        return 2
    fi
    for action in "${actions[@]}"; do
        "show_$action" || status=1
    done
    return "$status"
}

main "$@"
