eqnode_installer_version='v3.0.2'
readonly eqnode_installer_version

installer_session_state_file="${script_basedir}/.installsessionstate"
readonly installer_session_state_file

config_file="${script_basedir}/install.conf"
readonly config_file

typeset -A config
config=(
  [install_version]='auto'
  [running_user]='snode'
  [git_repository]='https://github.com/EquilibriaCC/Equilibria.git'
  [p2p_bind_port]=0
  [rpc_bind_port]=0
  [zmq_rpc_bind_port]=0
  [multi_node]=0
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
  [zmq_rpc_bind_port]=9232
)
readonly default_service_node_ports

load_config() {
#  grep -F "#" &>/dev/null
  while read line; do
    if echo "${line}" | grep -q "="; then
      varname=$(echo "${line}" | cut -d '=' -f 1)
      varvalue=$(echo "${line}" | cut -d '=' -f 2)
      config[${varname}]=${varvalue}
    fi
  done < ${config_file}
}

set_install_session_state() {
  local newstate="${1}"
  printf "%s" "${newstate}" > "${installer_session_state_file}"
}

read_install_session_state() {
  cat "${installer_session_state_file}"
}

load_config
