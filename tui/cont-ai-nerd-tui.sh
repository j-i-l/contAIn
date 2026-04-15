#!/usr/bin/env bash
# cont-ai-nerd-tui — Pure bash TUI for cont-ai-nerd

set -euo pipefail

CONFIG_FILE="${HOME}/.config/contain/config.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PG='\033[38;5;248m'
SH='\033[38;5;244m'
BO='\033[38;5;208m'
WH='\033[38;5;255m'
BOLD='\033[1m'
RS='\033[0m'
RESET='\033[0m'

clear_screen() { printf '\033[2J\033[H'; }
move_cursor() { printf '\033[%d;%dH' "$1" "$2"; }
hide_cursor() { printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }

draw_box() {
  local x1=$1 y1=$2 x2=$3 y2=$4 title="$5"
  local w=$((x2 - x1 - 1)) h=$((y2 - y1 - 1))
  
  move_cursor "$y1" "$x1"
  printf '+%s+' "$(printf '%0.s-' {1..$w})"
  
  for ((i = y1 + 1; i < y2; i++)); do
    move_cursor "$i" "$x1"
    printf '|'
    move_cursor "$i" "$((x1 + w + 1))"
    printf '|'
  done
  
  move_cursor "$y2" "$x1"
  printf '+%s+' "$(printf '%0.s-' {1..$w})"
  
  if [[ -n "$title" ]]; then
    local title_len=${#title}
    local title_pos=$((x1 + (w - title_len) / 2 + 1))
    move_cursor "$y1" "$title_pos"
    printf '%s' "$title"
  fi
}

load_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}Error: Config file not found. Run configure.sh first.${RESET}"
    exit 1
  fi
  
  PRIMARY_USER=$(jq -r '.primary_user // empty' "$CONFIG_FILE")
  PRIMARY_HOME=$(jq -r '.primary_home // empty' "$CONFIG_FILE")
  AGENT_USER=$(jq -r '.agent_user // "agent"' "$CONFIG_FILE")
  HOST=$(jq -r '.host // "127.0.0.1"' "$CONFIG_FILE")
  PORT=$(jq -r '.port // 3000' "$CONFIG_FILE")
  CONTAINER_NAME=$(jq -r '.agent_systems.opencode.container.name // "contain"' "$CONFIG_FILE")
  
  if [[ -z "$PRIMARY_USER" ]]; then
    echo -e "${RED}Error: Invalid config file.${RESET}"
    exit 1
  fi
}

get_container_status() {
  if systemctl is-active --quiet "${CONTAINER_NAME}.service" 2>/dev/null; then
    echo "running"
  else
    echo "stopped"
  fi
}

get_opencode_status() {
  local status
  if curl -s --connect-timeout 2 "http://${HOST}:${PORT}/health" >/dev/null 2>&1; then
    echo "online"
  else
    echo "offline"
  fi
}

draw_header() {
  local logo_width=39
  local pad=$(( (COLUMNS - logo_width) / 2 ))
  [[ $pad -lt 0 ]] && pad=0
  local sp
  sp=$(printf '%*s' "$pad" '')

  move_cursor 1 1
  echo -e "${sp}                    ${BO}▄▄${RS}        ${BO}▄▄${RS}       "
  echo -e "${sp}                ${SH}▒${PG}█${RS}  ${BO}█${SH}▒${WH}█▀▀▄${RS} ${WH}▀█▀${RS} ${BO}█${RS}       "
  echo -e "${sp} ${SH}▒${PG}█▀▄${RS} ${PG}▄▀▀▄${SH}▒${PG}█▀▀▄${RS} ${PG}▀█▀${RS} ${BO}█${SH}▒${WH}█▄▄█${RS} ${SH}▒${WH}█${RS}  ${BO}█${SH}▒${PG}█▀▀▄${RS}  "
  echo -e "${sp} ${SH}▒${PG}█${RS}  ${SH}▒${PG}█${RS} ${SH}▒${PG}█${SH}▒${PG}█${RS} ${SH}▒${PG}█${RS} ${SH}▒${PG}█${RS}  ${BO}█${SH}▒${WH}█${RS} ${SH}▒${WH}█${RS} ${SH}▒${WH}█${RS}  ${BO}█${SH}▒${PG}█${RS} ${SH}▒${PG}█${RS}  "
  echo -e "${sp}  ${PG}▀▀▀${RS}  ${PG}▀▀${RS}  ${PG}▀${RS}  ${PG}▀${RS}  ${PG}▀${RS}  ${BO}█${RS} ${WH}▀${RS}  ${WH}▀${RS} ${WH}▀▀▀${RS} ${BO}█${RS} ${PG}▀${RS}  ${PG}▀${RS}  "
  echo -e "${sp}                    ${BO}▀▀${RS}        ${BO}▀▀${RS}       "
  echo ""
}

draw_left_panel() {
  local selected_as=$1
  local h=$((LINES - 5))
  
  draw_box 1 8 "$((COLUMNS * 30 / 100))" "$h" "Agent Systems"
  
  move_cursor 10 $((COLUMNS * 30 / 100 - 20))
  echo -e "${CYAN}opencode${RESET}"
  
  if [[ "$selected_as" == "opencode" ]]; then
    move_cursor 10 $((COLUMNS * 30 / 100 - 23))
    echo -n "▶"
  fi
  
  move_cursor 12 $((COLUMNS * 30 / 100 - 20))
  echo "[enabled]"
}

draw_right_panel() {
  local selected_as=$1
  local selected_action=$2
  
  local x=$((COLUMNS * 30 / 100 + 2))
  local w=$((COLUMNS - COLUMNS * 30 / 100 - 4))
  local h=$((LINES - 5))
  
  draw_box "$x" 8 "$((COLUMNS - 1))" "$h" "Actions"
  
  local y=10
  move_cursor $y $((x + 2))
  echo -e "${BOLD}OpenCode Agent System${RESET}"
  
  y=$((y + 2))
  move_cursor $y $((x + 2))
  echo "Container: ${CONTAINER_NAME}"
  
  y=$((y + 1))
  move_cursor $y $((x + 2))
  echo "Server: ${HOST}:${PORT}"
  
  local status
  status=$(get_container_status)
  y=$((y + 1))
  move_cursor $y $((x + 2))
  if [[ "$status" == "running" ]]; then
    echo -e "Status: ${GREEN}Running${RESET}"
  else
    echo -e "Status: ${RED}Stopped${RESET}"
  fi
  
  y=$((y + 2))
  move_cursor $y $((x + 2))
  echo -e "${BOLD}Actions:${RESET}"
  
  local actions=("status" "start" "stop" "commit" "logs" "tui")
  for i in "${!actions[@]}"; do
    y=$((y + 1))
    move_cursor $y $((x + 2))
    if [[ $i -eq $selected_action ]]; then
      echo -e "  ▶ ${actions[$i]}"
    else
      echo -e "    ${actions[$i]}"
    fi
  done
}

draw_footer() {
  move_cursor $((LINES - 2)) 1
  echo -e "${BOLD}↑/↓:${RESET} Navigate  ${BOLD}Enter:${RESET} Execute  ${BOLD}q:${RESET} Quit"
}

execute_action() {
  local action=$1
  
  case "$action" in
    status)
      local cstatus=$(get_container_status)
      local ostatus=$(get_opencode_status)
      echo ""
      echo "Container: ${cstatus}"
      echo "OpenCode Server: ${ostatus}"
      read -p "Press Enter to continue..."
      ;;
    start)
      systemctl start "${CONTAINER_NAME}.service" 2>/dev/null || echo "Failed to start container"
      echo "Container started"
      sleep 1
      ;;
    stop)
      systemctl stop "${CONTAINER_NAME}.service" 2>/dev/null || echo "Failed to stop container"
      echo "Container stopped"
      sleep 1
      ;;
    commit)
      local ts=$(date +%Y%m%d-%H%M%S)
      podman commit "$CONTAINER_NAME" "localhost/contain:${ts}" 2>/dev/null
      podman tag "localhost/contain:${ts}" "localhost/contain:latest" 2>/dev/null
      echo "Container committed"
      sleep 1
      ;;
    logs)
      clear
      journalctl -u "${CONTAINER_NAME}.service" --no-pager -n 50 | less
      ;;
    tui)
      clear
      show_cursor
      echo "Launching OpenCode TUI..."
      exec opencode tui --hostname "$HOST" --port "$PORT"
      ;;
  esac
}

main() {
  load_config
  
  stty -echo
  
  local selected_as="opencode"
  local selected_action=0
  
  trap 'show_cursor; stty echo; exit 0' EXIT INT TERM
  
  while true; do
    clear_screen
    draw_header
    draw_left_panel "$selected_as"
    draw_right_panel "$selected_as" "$selected_action"
    draw_footer
    
    local key
    read -n1 key 2>/dev/null || break
    
    case "$key" in
      A|k) # up
        selected_action=$((selected_action > 0 ? selected_action - 1 : 0))
        ;;
      B|j) # down
        selected_action=$((selected_action < 5 ? selected_action + 1 : 5))
        ;;
      q)
        break
        ;;
      "")
        local actions=("status" "start" "stop" "commit" "logs" "tui")
        execute_action "${actions[$selected_action]}"
        ;;
    esac
  done
  
  clear_screen
  show_cursor
  stty echo
}

main "$@"