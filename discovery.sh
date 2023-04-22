
#
#
#typeset -A default_service_node_ports
#default_service_node_ports=(
#  [p2p_bind_port]=9230
#  [rpc_bind_port]=9231
#)
#readonly default_service_node_ports


#declare -A required_tool_package_map
#required_tool_package_map=(
#  [netstat]='net-tools'
#  [natsort]='python3-natsort'
#  [bc]='bc'
#  [grep]='grep'
#  [getopt]='util-linux'
#  [gawk]='gawk'
#)
#readonly required_tool_package_map

discover_system() {
  declare -n result="$1"
  result[distro]="$(lsb_release -a 2> /dev/null | grep -oP 'Distributor ID:\t+\K[a-zA-Z0-9-_\s]+' | awk '{ print tolower($1) }')"
  result[release]="$(lsb_release -a 2>/dev/null | grep 'Release:' | awk '{ print $2 }')"
  result[codename]="$(lsb_release -a 2>/dev/null | grep -oP 'Codename:\t+\K[a-zA-Z0-9-_\s]+')"
  result[memory]="$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{ print $2 }')"
  result[free_space_root_mount]="$(df /root | awk 'END{ print $4 }')"
  result[free_space_home_mount]="$(df /home | awk 'END{ print $4 }')"

  return 0
}

discover_daemons() {
  declare -n result="$1"
  local output_column="$2"
  local idx=0
  while read -r line; do
    result[${idx}]="${line}"
    idx=$((idx + 1))
  done <<< "$(sudo ps -f -o "${output_column}" -o args -ax | grep '[b]in/daemon.*--service-node' | gawk '{ print $1 }' | natsort | uniq )"

#while read -r line; do; echo "$line"; done <<< "$(sudo ps -f -o user,pid,stat -o args -ax | grep '[b]in/daemon.*--service-node' | tr -s '\t' ' ')"
#  discovered_daemons=${result[@]}
  return 0
}

discover_biggest_blockchain() {
  declare -A daemon_users

  discover_daemons daemon_users 'user'

  local biggest_blockchain blockchain_file blockchain_size blockchain_root
  local biggest_blockchain_size=0
  biggest_blockchain=

  for username in "${daemon_users[@]}"
  do
    blockchain_root="/home/${username}/.equilibria"
    blockchain_file="${blockchain_root}/lmdb/data.mdb"

    [[ ! -f "${blockchain_file}" ]] && continue

    blockchain_size="$(stat -c %s "${blockchain_file}")"

    if [[ "${blockchain_size}" -gt "${biggest_blockchain_size}" ]]; then
      biggest_blockchain="${blockchain_root}"
      biggest_blockchain_size="${blockchain_size}"
    fi
  done
  echo "${biggest_blockchain}"
}

daemons_found() {
   [[ "${#discovered_daemons[*]}" -ge 1 ]]
}

discover_active_installations() {
  declare -n result="$1"
  local process_id user_name session_state pid_exec_path
  local idx=0
  while read -r line; do
    read -r user_name process_id <<< "${line//;/ }"
    pid_exec_path="$(sudo pwdx "${process_id}" 2> /dev/null | grep -o '/.*')"

    if [[ "${pid_exec_path}" != "" ]] && [[ -f "${pid_exec_path}/.installsessionstate" ]]; then
      session_state="$(cat "${pid_exec_path}/.installsessionstate")"
    fi
    result[${idx}]="${user_name};${process_id};${session_state};${pid_exec_path}"
    idx=$((idx + 1))
  done <<< "$(sudo ps aux | grep '[b]ash.*eqsnode.sh' | grep -v '[s]udo' | gawk '{ printf("%s;%s\n", $1, $2) }')"

  return 0
}
#
#active_installations_found() {
#   [[ "${#discovered_active_installations[*]}" -ge 1 ]]
#}

discover_free_port_sets() {
    declare -n result="$1"
    local number_of_sets="$2"
    local sets_counter=0

    # find available ports
    local port_increment=100
    local p2p_port rpc_port validation_result
    p2p_port=${default_service_node_ports[p2p_bind_port]}
    rpc_port=${default_service_node_ports[rpc_bind_port]}

    while true; do
      validation_result="$(validate_port "${p2p_port}") $(validate_port "${rpc_port}")"

      # break if all three ports are available and within allowed port range
      if [[ $(echo "${validation_result}" | grep -o -e 'free_port' | wc -l) -eq 2 ]]; then
        sets_counter=$((sets_counter + 1))
        result["set${sets_counter}__p2p_bind_port"]="${p2p_port}"
        result["set${sets_counter}__rpc_bind_port"]="${rpc_port}"

        [[ "${sets_counter}" -eq "${number_of_sets}" ]] && break

      # break if at least one port is outside of the allowed port range
      elif [[ $(echo "${validation_result}" | grep -c 'outside_port_range') -eq 1 ]]; then
        return 1
      fi
      p2p_port=$((p2p_port + port_increment))
      rpc_port=$((rpc_port + port_increment))
    done

    return 0
}

validate_port() {
  local port="$1"

  if [ "${port}" -lt 5000 ] || [ "${port}" -gt 49151 ]; then
    echo "outside_port_range"

  elif [[ "$(sudo netstat -lnp | grep -c ":${port}")" -gt 0 ]]; then
    echo "port_used"
  else
    echo "free_port"
  fi
}

discover_available_usernames() {
    declare -n result="$1"
    local number_of_usernames="$2"
    local username_base="$3"
    local idx=1
    local suffix=1

    candidate_username=${username_base}
    while true ; do
      if ! id -u "${candidate_username}" >/dev/null 2>&1; then
        result["${idx}"]="${candidate_username}"
        idx=$((idx + 1))

        [[ "${idx}" -gt "${number_of_usernames}" ]] && break;
      fi
      suffix=$((suffix + 1))
      candidate_username="${username_base}${suffix}"
    done
}
