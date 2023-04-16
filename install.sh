#!/usr/bin/env bash
# by Mister R

set -o errexit
set -o nounset
set -euo pipefail

script_basedir=$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")
readonly script_basedir

source "${script_basedir}/common.sh"

installer_home=
auto_find_result=
forced_running_user=0

main() {
  print_splash_screen
  install_dependencies

  if ! [[ "${#}" -eq "0" ]]; then
    case "$1" in
       multi-node) multi_node_command_handler "$@" ;;
       *) echo -e "Unsupported option $1\n"
          usage
          exit 0
          ;;
    esac
  fi

  determine_running_user_and_set_config_if_needed
  init
  install_checks
  setup_running_user
  copy_installer_or_continue_session
  install_with_running_user
  finish_install
}

print_splash_screen () {
  cat <<'SPLASHMSG'

  _____            _ _ _ _          _
 | ____|__ _ _   _(_) (_) |__  _ __(_) __ _
 |  _| / _` | | | | | | | '_ \| '__| |/ _` |
 | |__| (_| | |_| | | | | |_) | |  | | (_| |
 |_____\__, |\__,_|_|_|_|_.__/|_|  |_|\__,_|
          |_|

SPLASHMSG
  echo -e "Service node installer script ${eqnode_installer_version}\n"
}

install_dependencies() {
  echo -e "\n\033[1mChecking basic dependencies...\033[0m"

  if ! [[ -x "$(command -v netstat)" ]]; then
    sudo apt -y install net-tools
  fi
  if ! [[ -x "$(command -v natsort)" ]]; then
    sudo apt -y install python3-natsort
  fi
  if ! [[ -x "$(command -v bc)" ]]; then
    sudo apt -y install bc
  fi
  if ! [[ -x "$(command -v grep)" ]]; then
    sudo apt -y install grep
  fi
}

multi_node_command_handler() {
  local port_option_found=0
  config['multi_node']=1

  args="$(getopt -a -n multi-node -o "pam:u:" --long preview-auto-magic,auto-ports,manual-ports:,user: -- "$@")"
  eval set -- "${args}"

  while :
  do
    case "$1" in
                                    # ignore --auto-ports if manual port options already set
      -a | --auto-ports)            if [[ "${port_option_found}" -eq 1 ]]; then shift; continue; fi;
                                    port_option_found=1 ; auto_ports_handler; shift ;;

                                    # ignore preview-auto-magic if port options set, if not show list and exit 0
      -p | --preview-auto-magic)    if [[ "${port_option_found}" -eq 1 ]]; then shift; continue; fi;
                                    preview_auto_magic_handler; exit 0 ;;

                                    # ignore --manual-ports if auto port options already set
      -m | --manual-ports)          if [[ "${port_option_found}" -eq 1 ]]; then shift 2; continue; fi;
                                    port_option_found=1 ; manual_ports_handler "$2" ; shift 2 ;;

                                    # option --user can be used in combination with both --auto-parts or --manual-ports option
      -u | --user)                  user_option_handler "$2"; shift 2 ;;
      --)                           shift; break ;;
      *)                            echo "Unexpected multi_node option" ; exit 1 ;;
    esac
  done
  # if no port option is specified by the user, use default '--auto-ports'
  if [[ "${port_option_found}" -eq 0 ]]; then
    auto_ports_handler
  fi
}

auto_ports_handler() {
  local auto_find_result

  echo -e "\n\033[1mAuto-detecting available ports...\033[0m"
  auto_find_ports_and_set_config_if_found

  if [[ "${auto_find_result}" = 'success' ]]; then
    echo -e "Detected available p2p_bind_port \t-> port ${config[p2p_bind_port]}"
    echo -e "Detected available rpc_bind_port \t-> port ${config[rpc_bind_port]}"
    echo -e "Detected available zmq_rpc_bind_port \t-> port ${config[zmq_rpc_bind_port]}"
  fi
}

preview_auto_magic_handler() {
  auto_ports_handler
  echo -e "\nIf needed you can alter and set these ports manually by:\n\n    \033[0;33mbash install.sh multi-node -m p2p:9330,rpc:9331,zmq:9332\033[0m\n"

  auto_search_available_username
  echo -e "\nIf needed you can alter and set the username manually by:\n\n    \033[0;33mbash install.sh multi-node -u mysnodeuser\033[0m"
}

user_option_handler() {
  local username="$1"
  forced_running_user=1
  config[running_user]="${username}"
}

auto_find_ports_and_set_config_if_found() {
    # find available ports
    local port_increment=100
    local p2p_port rpc_port zmq_rpc_port validation_result
    p2p_port=${default_service_node_ports[p2p_bind_port]}
    rpc_port=${default_service_node_ports[rpc_bind_port]}
    zmq_rpc_port=${default_service_node_ports[zmq_rpc_bind_port]}

    while true; do
      validation_result="$(validate_port "${p2p_port}") $(validate_port "${rpc_port}") $(validate_port "${zmq_rpc_port}")"

      # break if all three ports are available and within allowed port range
      if [[ $(echo "${validation_result}" | grep -o -e 'free_port' | wc -l) -eq 3 ]]; then
        config[p2p_bind_port]="${p2p_port}"
        config[rpc_bind_port]="${rpc_port}"
        config[zmq_rpc_bind_port]="${zmq_rpc_port}"
        auto_find_result="success"
        break;

      # break if one or more ports are outside of the allowed port trange
      elif [[ $(echo "${validation_result}" | grep -o -e 'outside_port_range' | wc -l) -gt 0 ]]; then
        auto_find_result="failed"
        break;
      fi
      p2p_port=$(bc -l <<< "($p2p_port + $port_increment)")
      rpc_port=$(bc -l <<< "($rpc_port + $port_increment)")
      zmq_rpc_port=$(bc -l <<< "($zmq_rpc_port + $port_increment)")
    done
}

manual_ports_handler() {
  if valid_manual_port_string_format "$1" ; then
    parse_manual_port_string_and_set_config_if_valid "$1"
  else
    echo -e "Invalid --manual-ports config format '$1'\n"
    usage
  fi
}

parse_manual_port_string_and_set_config_if_valid() {
  typeset -A key_to_config_param
  key_to_config_param=(
    [p2p]='p2p_bind_port'
    [rpc]='rpc_bind_port'
    [zmq]='zmq_rpc_bind_port'
  )
  local params validation_result port_error

  # shellcheck disable=SC2207
  # basically split manual port string on separator ','
  params=( $(echo "$1" | egrep -o -e "[^,]+") )
  port_error=0

  echo -e "\033[1mReading manual port configuration...\033[0m"

  # check unique ports
  if [[ "$(echo "$1" | egrep -o -e "[0-9]{2,}" | natsort | uniq | wc -l)" -ne 3 ]]; then
    echo -e "\033[0;33mAll ports in the manual port configuration should have a unique port assigned\033[0m\n"
    exit 1
  fi

  for key_value in "${params[@]}"
  do
    # split key_value pair on divider ':'
    read -r port_key port_value <<< "${key_value//:/ }"
    validation_result="$(validate_port "${port_value}")"

    case "${validation_result}" in
      'outside_port_range') printf "%s: %d \t-> \033[0;33mOut of range [allowed between 5000-49151]\033[0m\n" "${key_to_config_param[${port_key}]}" "${port_value}"
                            port_error=1 ;;

      'port_used')          printf "%s: %d \t-> \033[0;33mEin use\033[0m\n" "${key_to_config_param[${port_key}]}" "${port_value}"
                            port_error=1 ;;

      'free_port')          printf "%s: %d \t-> OK\n" "${key_to_config_param[${port_key}]}" "${port_value}"
                            config["${key_to_config_param[${port_key}]}"]="${port_value}" ;;

      *)                    echo "Unknown port validation result" ; exit 1 ;;
    esac
  done
  if [[ "${port_error}" -eq 1 ]]; then
    exit 1
  fi
}

valid_manual_port_string_format() {
  [[ "$(echo "$1" | egrep -o -e "^[a-z2]{3}:[0-9]+,[a-z2]{3}:[0-9]+,[a-z2]{3}:[0-9]+$" | egrep -o -e "p2p:[0-9]+" -e "rpc:[0-9]+" -e "zmq:[0-9]+" | wc -l )" -eq 3 ]]
}

validate_port() {
  local port="$1"

  if [ "${port}" -lt 5000 ] || [ "${port}" -gt 49151 ]; then
    echo "outside_port_range"

  elif [[ "$(sudo netstat -lnp | grep ":${port}" | wc -l)" -gt 0 ]]; then
    echo "port_used"
  else
    echo "free_port"
  fi
}

init() {
  [[ "${config[running_user]}" = "root" ]] && homedir='/root' || homedir="/home/${config[running_user]}"
  installer_home="${homedir}/eqnode_installer"
}

install_checks () {
  echo -e "\n\033[1mExecuting pre-install checks...\033[0m"
  inspect_time_services
}

inspect_time_services () {
  echo -e "\n\033[1mChecking clock NTP synchronisation...\033[0m"

  if  [[ -x "$(command -v timedatectl)" ]]; then
    if [[ $(sudo timedatectl | grep -o -e 'synchronized: yes' -e 'service: active' | wc -l) -ne 2 ]]; then
      echo -e "\n\033[0;33mERROR: Clock NTP synchronisation is not working correctly. This is required to run a stable service node. Please fix 'timedatectl' before continuing.\033[0m\n"
      timedatectl
      exit 1
    fi
  else
    echo -e "\033[0;33mWARNING: Clock NTP synchronisation could not be verified.\nPlease check and make sure this is working before continuing!\033[0m\n"
    while true; do
      read -p $'\033[1mAre you sure you want to continue?\e[0m (NOT RECOMMENDED) [Y/N]: ' yn
      yn=${yn:-N}

      case $yn in
            [Yy]* ) break;;
            [Nn]* ) exit 1;;
            * ) echo -e "(Please answer Y or N)";;
      esac
    done
  fi
}

determine_running_user_and_set_config_if_needed() {
  # if not in multi-node mode and not --username set, auto-scan for an available username for running user
  if [[ "${config[multi_node]}" -eq 1 ]] && [[ "${forced_running_user}" -eq 0 ]]; then
    auto_search_available_username
  fi
}

auto_search_available_username() {
    echo -e "\n\033[1mAuto-searching for an unused username to run the service node...\033[0m"
    local username_base counter
    username_base="${config[running_user]}"
    counter=1
    candidate_username=${username_base}
    while true; do
      if ! id -u "${candidate_username}" >/dev/null 2>&1; then
        echo "Detected unused username -> ${candidate_username}"
        config[running_user]="${candidate_username}"
        break
      fi
      counter=$((counter + 1))
      candidate_username="${username_base}${counter}"
    done
}

setup_running_user () {
  create_running_user_if_needed
  sudoers_running_user_nopasswd 'add'
}

create_running_user_if_needed() {
   # shellcheck disable=SC2154
   if ! id -u "${config[running_user]}" >/dev/null 2>&1; then
     echo -e "\n\033[1mCreating sudo user '${config[running_user]}' to run service node...\033[0m"
     echo -e "\n\033[0;33mWe need to create a user '${config[running_user]}' to run the service node. You will be asked to enter a password for this user next. Please make sure to keep this password safe.\033[0m\n"
     read -n 1 -s -r -p "Press ANY key to continue"

     sudo adduser --gecos GECOS "${config[running_user]}"
     sudo usermod -aG sudo "${config[running_user]}"
   fi
}

sudoers_running_user_nopasswd() {
  local action="$1"
  local sudo_settings sed_command
  [[ "${action}" = 'add' ]] && sudo_settings='ALL=(ALL) NOPASSWD:ALL' || sudo_settings='ALL=(ALL:ALL) ALL'
  # shellcheck disable=SC2116
  sed_command="$(echo "/^${config[running_user]} /{h;s/ .*/ ${sudo_settings}/};\${x;/^$/{s//${config[running_user]} ${sudo_settings}/;H};x}")"
  sudo sed -i "${sed_command}" /etc/sudoers
}

copy_installer_or_continue_session() {
  if [[ -d "${installer_home}" ]]; then
    if [[ -f "${installer_home}/.installsessionstate" ]] && [[ "$(cat "${installer_home}/.installsessionstate")" = "${installer_state[finished_eqsnode_install]}" ]]; then
      echo -e "\033[0;33mA finished installation of an Equilibria service node has been found! This installation script is ONLY for fresh installations not for updating a service node.\033[0m"
      exit 0
    fi

    echo -e "\n\033[1mA previous installation session has been detected with the following config:\033[0m"
    # Echo install.conf, while skipping #-comment lines
    cat "${installer_home}/install.conf" | egrep "^[^#].*"
    echo ""

    while true; do
      read -p 'Do you want to continue this session? (press ENTER to for: yes) [Y/N]: ' yn
      yn=${yn:-Y}

      case $yn in
            [Yy]* ) break;;
            [Nn]* ) copy_installer_to_install_user_homedir
                    break;;
            * ) echo -e "(Please answer Y or N)";;
      esac
    done
  else
    copy_installer_to_install_user_homedir
  fi
}

copy_installer_to_install_user_homedir() {
  [[ -d "${installer_home}" ]] && echo -e "\033[1mDeleting old installer files...\033[0m" && sudo rm --recursive --force -- "${installer_home}"

  echo -e "\n\033[1mCopying installer to '${installer_home}'...\033[0m"
  sudo mkdir "${installer_home}"
  sudo cp eqsnode.sh eqnode.service.template common.sh "${installer_home}"
  write_install_config_to_install_user_homedir
  sudo chown -R "${config[running_user]}":root "${installer_home}"
}

write_install_config_to_install_user_homedir() {
  local install_file_user_home
  install_file_user_home="${installer_home}/install.conf"

  echo -e "\n\033[1mGenerating new install.conf in '${install_file_user_home}'...\033[0m"

  sudo touch "${install_file_user_home}"

  for key in "${!config[@]}"
  do
    echo -e "${key}=${config[${key}]}" | sudo tee -a "${install_file_user_home}"
  done
}

install_with_running_user() {
  sudo -H -u "${config[running_user]}" bash -c 'cd ~/eqnode_installer/ && bash eqsnode.sh install'
}

finish_install() {
  sudoers_running_user_nopasswd 'remove'
  echo -e "\n\033[1mInstallation of Service Node completed.\033[0m\n"
  echo -e "\033[0;33mPlease DO NOT forget to link a wallet to the new service node! This is done by copy and pasting the command line, obtained during the 'prepare_sn' step, into the wallet. Only then the activation of the service node will be complete and available for staking!\033[0m\n"
  su - "${config[running_user]}"
}

usage() {
  cat <<USAGEMSG
bash $0 [COMMAND...] [OPTIONS...]

Commands:
  <empty>                   Install a single service node with default ports
  multi-node                Installs an additional service node on the same VPS or server

Multi-node command options:
  -a  --auto-ports          Default; Automatically assign non-default ports
  -p  --preview-auto-magic  Display preview of '--auto-ports' and auto-search of username
  --manual-ports [config]   Format config (without spaces) 'p2p:<port>,rpc:<port>,zmq:<port>'
                            Example: --manual-ports p2p:9330,rpc:9331,zmq:9332

  -u --user [name]          Set user that will run the service node
                            Example: --user snode2

Options:
  -?  -h  --help                Show this help text
USAGEMSG
}

usage_help_is_needed() {
  [[ ( "${#}" -ge "1" && ( "$1" = '-h' || "$1" = '--help' || "$1" = '-?' )) ]]
}

finally() {
  result=$?
  echo ""
  exit ${result}
}
trap finally EXIT ERR INT

if usage_help_is_needed "$@"; then
  usage
  exit 0
fi

main "${@}"
exit 0
