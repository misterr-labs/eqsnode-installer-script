eqnode_installer_version='v5.2.0'
readonly eqnode_installer_version

version_regex="^v[0-9]+.[0-9]+.[0-9]+$"
readonly version_regex

rev_hash_regex="^[0-9a-f]{5,40}$"
readonly rev_hash_regex

installer_session_state_file="${script_basedir}/.installsessionstate"
readonly installer_session_state_file


typeset -A config
config=(
  [nodes]=1
  [install_version]='auto'
  [running_user]='snode'
  [required_cmake_version]='3.28'
  [git_repository]='https://github.com/EquilibriaCC/Equilibria.git'
  [p2p_bind_port]=9230
  [rpc_bind_port]=9231
  [daemon_log_level]=
  [daemon_no_fluffy_blocks]=0
)

typeset -A installer_state
installer_state=(
  [started]='started'
  [install_packages]='install_packages'
  [checkout_git]='checkout_git'
  [compile_move]='compile_move'
  [install_service]='install_service'
  [enable_service]='enable_service'
  [start_service]='start_service'
  [watch_daemon]='watch_daemon'
  [ask_prepare]='ask_prepare'
  [finished_eqsnode_install]='finished_eqsnode_install'
)
readonly installer_state

typeset -A default_service_node_ports
default_service_node_ports=(
  [p2p_bind_port]=9230
  [rpc_bind_port]=9231
)
readonly default_service_node_ports

load_config() {
  local config_file="$1"
  local -n config_ref="$2"
  if [[ -f "${config_file}" ]]; then
    while read line; do
      if echo "${line}" | grep -q "="; then
        varname=$(echo "${line}" | cut -d '=' -f 1)
        varvalue=$(echo "${line}" | cut -d '=' -f 2)
        config_ref[${varname}]=${varvalue}
      fi
    done < ${config_file}
  fi
}

write_config() {
  local -n node_config_ref="$1"
  local install_file_conf_path="$2"

  if [[ -f "${install_file_conf_path}" ]]; then
    sudo rm -Rf "${install_file_conf_path}"
  fi
  sudo touch "${install_file_conf_path}"

  for key in "${!node_config_ref[@]}"
  do
    echo -e "${key}=${node_config_ref[${key}]}" | sudo tee -a "${install_file_conf_path}"
  done
  sudo chown "${node_config_ref[running_user]}":root "${install_file_conf_path}"
}

set_install_session_state() {
  local newstate="${1}"
  printf "%s" "${newstate}" > "${installer_session_state_file}"
}

read_install_session_state() {
  cat "${installer_session_state_file}"
}

default_ports_configured() {
  [[
    "${config[p2p_bind_port]}" -eq "${default_service_node_ports[p2p_bind_port]}" &&
    "${config[rpc_bind_port]}" -eq "${default_service_node_ports[rpc_bind_port]}"
  ]]
}

get_latest_equilibria_version_number() {
  git ls-remote --tags "${config[git_repository]}" 2>/dev/null | grep -o 'v.*' | sort -V | tail -1
}

version2num() {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1, $2, $3, $4); }'
}
