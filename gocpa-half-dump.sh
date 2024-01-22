#!/usr/bin/env bash
#
# Скрипт, создающий дамп боевой базы данных с данными за последнее время
#
# Usage:
#   ./gocpa-half-dump.sh <options>...
#
# Update:
# curl -o gocpa-half-dump.sh https://raw.githubusercontent.com/gocpa/half-dump-action/master/gocpa-half-dump.sh
# chmod +x gocpa-half-dump.sh
#
# touch .sqlpwd
# chmod 600 .sqlpwd
# chown $USER:nogroup .sqlpwd
# 
# .sqlpwd content:
# [client]
# host=
# user=
# password=
#

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail
# Turn on traces, useful while debugging but commented out by default
# set -o xtrace

usage() {
  cat <<EOF
GoCPA Half Dump v1.0.0

Usage:
./$(basename "${BASH_SOURCE[0]}") \\
  --dumpfile dump.sql \\
  --database-from productionDatabase \\
  --database-to stagingDatabase \\
  --tables-skip "job_batches jobs failed_jobs health_check_result_history_items password_reset_tokens personal_access_tokens queue_monitor pulse_aggregates pulse_entries pulse_values telescope_entries telescope_entries_tags telescope_monitoring" \\
  --tables-bydate "pixel_log" \\
  --dump-ago 7 \\
  --maxsize 5000000

Script description here.

Available options:

-h, --help                     Print this help and exit
-v, --verbose                  Print script debug info
--dumpfile tmp.sql             Путь к файлу, в который будет делаться дамп
--database-from dbname         Export database name
--database-to dbname-dump      Import database name
--tables-skip "table1 table2"  Tables to skip, space separated
--tables-bydate "log users"    Tables to dump latest data, space separated
--dump-ago 7                   Days to dump, default 7
--maxsize 5000000              Size in bytes, which can be dumped without warning, default 5000000
EOF
  exit
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT

  if [ ! -z "$DUMPFILE" ]; then
    if [ -f "$DUMPFILE" ]; then
      rm $DUMPFILE
    fi
  fi
}

trap cleanup SIGINT SIGTERM ERR

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT="\033[0m" BOLD="\033[1m" DIM="\033[2m" RED="\033[0;31m" GREEN="\033[0;32m" YELLOW="\033[0;33m"
  else
    NOFORMAT="" BOLD="" DIM="" RED="" GREEN="" YELLOW=""
  fi
}

function log () {
  setup_colors
  local log_level="${1}"
  shift

  # shellcheck disable=SC2034
  local color_debug=$DIM
  # shellcheck disable=SC2034
  local color_info=$NOFORMAT
  # shellcheck disable=SC2034
  local color_warning=$YELLOW
  # shellcheck disable=SC2034
  local color_error=$RED
  # shellcheck disable=SC2034
  local color_alert=$RED
  # shellcheck disable=SC2034
  local color_emergency="\\x1b[1;4;5;37;41m"

  local colorvar="color_${log_level}"

  local color="${!colorvar:-${color_error}}"
  local color_reset="\\x1b[0m"

  if [[ "${NO_COLOR:-}" = "true" ]] || { [[ "${TERM:-}" != "xterm"* ]] && [[ "${TERM:-}" != "screen"* ]]; } || [[ ! -t 2 ]]; then
    if [[ "${NO_COLOR:-}" != "false" ]]; then
      # Don't use colors on pipes or non-recognized terminals
      color=""; color_reset=""
    fi
  fi

  # all remaining arguments are to be printed
  local log_line=""

  while IFS=$'\n' read -r log_line; do
    echo -e "$(date +"%H:%M:%S") ${color}$(printf "[%s]" "${log_level}")${color_reset} ${log_line}" 1>&2
  done <<< "${@:-}"
}

function emergency () {  log emergency "${@}"; true; }
function warning ()   {  log warning "${@}"; true; }
function info ()      {  log info "${@}"; true; }
function debug ()     {  log debug "${@}"; true; }

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  emergency "$msg"
  exit "$code"
}

parse_params() {
  # default values of variables set from params
  DUMPFILE=''
  DATABASE_FROM=''
  DATABASE_TO=''
  TABLES_SKIP=''
  TABLES_DUMP_BYDATE=''
  DUMP_AGO=7
  MAXSIZE=5000000

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    --dumpfile)
      DUMPFILE="${2-}"
      shift
      ;;
    --database-from)
      DATABASE_FROM="${2-}"
      shift
      ;;
    --database-to)
      DATABASE_TO="${2-}"
      shift
      ;;
    --tables-skip)
      TABLES_SKIP=("${2-}")
      shift
      ;;
    --tables-bydate)
      TABLES_DUMP_BYDATE=("${2-}")
      shift
      ;;
    --dump-ago)
      DUMP_AGO="${2-}"
      shift
      ;;
    --maxsize)
      MAXSIZE="${2-}"
      shift
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  # check required params and arguments
  [[ -z "${DUMPFILE-}" ]] && usage
  # [[ -z "${DATABASE_FROM-}" ]] && die "Missing required parameter: DATABASE_FROM"
  # [[ -z "${DATABASE_TO-}" ]] && die "Missing required parameter: DATABASE_TO"

  return 0
}

export_dump() {
  local TABLES_WITH_CREATED_AT=($(mysql --defaults-extra-file=.sqlpwd "$DATABASE_FROM" -e "SELECT TABLE_NAME FROM information_schema.columns WHERE TABLE_SCHEMA = '${DATABASE_FROM}' AND COLUMN_NAME = 'created_at';" | awk '{print $1}' | grep -v '^TABLE_NAME' ))
  local TABLES_WITH_DATETIME=($(mysql --defaults-extra-file=.sqlpwd "$DATABASE_FROM" -e "SELECT TABLE_NAME FROM information_schema.columns WHERE TABLE_SCHEMA = '${DATABASE_FROM}' AND COLUMN_NAME = 'datetime';" | awk '{print $1}' | grep -v '^TABLE_NAME' ))
  local TABLES_WITH_DATE=($(mysql --defaults-extra-file=.sqlpwd "$DATABASE_FROM" -e "SELECT TABLE_NAME FROM information_schema.columns WHERE TABLE_SCHEMA = '${DATABASE_FROM}' AND COLUMN_NAME = 'date';" | awk '{print $1}' | grep -v '^TABLE_NAME' ))

  info "Dumping database structure for ${BOLD}${DATABASE_FROM}${NOFORMAT}:"
  mysqldump --defaults-extra-file=.sqlpwd "$DATABASE_FROM" --no-data --skip-add-drop-table > $DUMPFILE
  local PREVIOUS_FILE_INFO=$(wc -c "$DUMPFILE" | awk '{print $1}')
  info "${GREEN}Result: [OK]${NOFORMAT}"

  echo ""

  info "Dumping data:"
  local TABLES=($(mysql --defaults-extra-file=.sqlpwd "$DATABASE_FROM" -e "SHOW TABLES;" | awk '{print $1}' | grep -v '^Tables_in' ))
  length=${#TABLES[@]}

  local ITER=0
  for ((i=0; i<$length; i++))
  do
    ITER=$(expr $ITER + 1)
    local TABLENAME=${TABLES[$i]}
    info "[${ITER}/${#TABLES[@]}] Dumping table ${BOLD}${TABLENAME}${NOFORMAT}:"
    
    # by default export all (WHERE true),
    # but if table is in TABLES_DUMP_BYDATE, export only data from last DUMP_AGO days
    local WHEREPARAM="true"
    local WHERE=""
    if [[ " ${TABLES_SKIP[@]} " =~ " ${TABLENAME} " ]]; then
      info "${DIM}Result: [SKIP]${NOFORMAT}"
      continue 1
    elif [[ " ${TABLES_DUMP_BYDATE[@]} " =~ " ${TABLENAME} " ]]; then
      if [[ " ${TABLES_WITH_CREATED_AT[@]} " =~ " ${TABLENAME} " ]]; then
        WHEREPARAM="DATE(\`created_at\`) >= DATE(NOW() - INTERVAL ${DUMP_AGO} DAY)"
        WHERE="where ${DIM}created_at >= NOW() - INTERVAL ${DUMP_AGO} DAYS${NOFORMAT}"
      elif [[ " ${TABLES_WITH_DATETIME[@]} " =~ " ${TABLENAME} " ]]; then
        WHEREPARAM="DATE(\`datetime\`) >= DATE(NOW() - INTERVAL ${DUMP_AGO} DAY)"
        WHERE="where ${DIM}datetime >= NOW() - INTERVAL ${DUMP_AGO} DAYS${NOFORMAT}"
      elif [[ " ${TABLES_WITH_DATE[@]} " =~ " ${TABLENAME} " ]]; then
        WHEREPARAM="\`date\` >= DATE(NOW() - INTERVAL ${DUMP_AGO} DAY)"
        WHERE="where ${DIM}date >= NOW() - INTERVAL ${DUMP_AGO} DAYS${NOFORMAT}"
      else
        die "Table $TABLENAME doesn't have any datetime field"
      fi
    fi

    mysqldump --defaults-extra-file=.sqlpwd "$DATABASE_FROM" "$TABLENAME" --opt --where="$WHEREPARAM" >> $DUMPFILE

    # Compute table size
    local TABLE_SIZE=$(($(wc -c "$DUMPFILE" | awk '{print $1}') - $PREVIOUS_FILE_INFO))
    info "${GREEN}Result: [OK]${NOFORMAT} ${WHERE}"

    if [ $TABLE_SIZE -gt $MAXSIZE ]; then
        warning "${YELLOW}Warning: ${TABLENAME} size is too big: ${RED}`echo $TABLE_SIZE | numfmt --to=iec-i --suffix=B`${NOFORMAT}"
    fi
    
    # Remember table size for next iteration
    PREVIOUS_FILE_INFO=$(wc -c "$DUMPFILE" | awk '{print $1}')

  done

  echo ""
  info "${GREEN}Done!${NOFORMAT}"
}

import_dump() {
  echo ""

  info "Deleting all old tables from ${BOLD}${DATABASE_TO}${NOFORMAT}:"
  mysql --defaults-extra-file=.sqlpwd --silent --skip-column-names -e "SHOW TABLES" $DATABASE_TO | xargs -I% echo 'SET FOREIGN_KEY_CHECKS = 0; DROP TABLE `%`; SET FOREIGN_KEY_CHECKS = 1;' | mysql --defaults-extra-file=.sqlpwd --silent $DATABASE_TO
  info "${GREEN}Result: [OK]${NOFORMAT}"

  echo ""

  info "Importing dump to ${BOLD}${DATABASE_TO}${NOFORMAT}:"
  cat $DUMPFILE | mysql --defaults-extra-file=.sqlpwd $DATABASE_TO
  info "${GREEN}Result: [OK]${NOFORMAT}"
  
  echo ""
  info "${GREEN}Done!${NOFORMAT}"
}

# script logic here
parse_params "$@"
setup_colors

info "${RED}Running gocpa-half-dump.sh:${NOFORMAT}"
info "${YELLOW}* DUMPFILE:${NOFORMAT}           ${DUMPFILE}"
info "${YELLOW}* DATABASE_FROM:${NOFORMAT}      ${DATABASE_FROM}"
info "${YELLOW}* DATABASE_TO:${NOFORMAT}        ${DATABASE_TO}"
info "${YELLOW}* TABLES_SKIP:${NOFORMAT}        ${TABLES_SKIP}"
info "${YELLOW}* TABLES_DUMP_BYDATE:${NOFORMAT} ${TABLES_DUMP_BYDATE}"
info "${YELLOW}* DUMP_AGO:${NOFORMAT}           ${DUMP_AGO}"
info "${YELLOW}* MAXSIZE:${NOFORMAT}            `echo $MAXSIZE | numfmt --to=iec-i --suffix=B`"
echo ""

[[ ! -z "${DATABASE_FROM-}" ]] && export_dump
[[ ! -z "${DATABASE_TO-}" ]] && import_dump

exit 0