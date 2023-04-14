eqnode_installer_version='v2.0'
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
