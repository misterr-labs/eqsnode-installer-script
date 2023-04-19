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

typeset -A command_options_set
command_options_set=(
  [help]=0
  [inspect_auto_magic]=0
  [multi_node]=0
  [ports]=0
  [skip_prepare_sn]=0
  [user]=0
  [version]=0
)
ports_option_value=
user_option_value=
version_option_value=

main() {
  print_splash_screen
  install_dependencies
  process_command_line_args "$@"

#  echo "${config[*]}"
#  exit 0
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
  if ! [[ -x "$(command -v netstat)" && -x "$(command -v natsort)" && -x "$(command -v bc)" && -x "$(command -v grep)" && -x "$(command -v getopt)" && -x "$(command -v gawk)" ]]; then
    echo -e "\n\033[1mFixing required dependencies....\033[0m"
    sudo apt -y install net-tools python3-natsort bc grep util-linux gawk
  fi
}

process_command_line_args() {
  parse_command_line_args "$@"
  validate_parsed_command_line_args
  set_config_and_execute_info_commands
}

parse_command_line_args() {
  args="$(getopt -a -n installer -o "himp:u:v:" --long help,inspect-auto-magic,multi-node,auto-ports,skip-prepare-sn,ports:,user:,version: -- "$@")"
  eval set -- "${args}"

  while :
  do
    case "$1" in
      -h | --help)                  command_options_set[help]=1 ; shift ;;
      -i | --inspect-auto-magic)    command_options_set[inspect_auto_magic]=1; shift; ;;
      -m | --multi-node)            command_options_set[multi_node]=1; shift ;;
      -p | --ports)                 command_options_set[ports]=1; ports_option_value="$2"; shift 2 ;;
      --skip-prepare-sn)            command_options_set[skip_prepare_sn]=1 ; shift ;;
      -u | --user)                  command_options_set[user]=1; user_option_value="$2"; shift 2 ;;
      -v | --version)               command_options_set[version]=1; version_option_value="$2"; shift 2 ;;
      --)                           shift ; break ;;
      *)                            echo "Unexpected option: $1" ;
                                    usage
                                    exit 0 ;;
    esac
  done
}

set_config_and_execute_info_commands() {

  # info commands, exit 0 must be first listed options in this function
  [[ "${command_options_set[inspect_auto_magic]}" -eq 1 ]] && inspect_auto_magic_option_handler && exit 0
  [[ "${command_options_set[help]}" -eq 1 ]] && usage && exit 0

  # direct set config
  [[ "${command_options_set[multi_node]}" -eq 1 && "${command_options_set[user]}" -eq 0 ]] && user_option_handler "auto"
  [[ "${command_options_set[user]}" -eq 1 ]] && user_option_handler "${user_option_value}"
  [[ "${command_options_set[skip_prepare_sn]}" -eq 1 ]] && config[skip_prepare_sn]=1
  [[ "${command_options_set[version]}" -eq 1 ]] && config[install_version]="${version_option_value}"

  # process more complex set config
  [[ "${command_options_set[ports]}" -eq 1 ]] && ports_option_handler "${ports_option_value}"

  # set default port option if none is set
  [[ "${command_options_set[ports]}" -eq 0 ]] && ports_option_handler "auto"

  # necessary return 0
  return 0
}

validate_parsed_command_line_args() {
  local friendly_option_groupings group_option_count command_options_set_string unique_count valid_option_combi_found
  valid_option_combi_found=0

  friendly_option_groupings=(
    "<no_options_set>"
    "multi_node ports user skip_prepare_sn version"
    "inspect_auto_magic"
    "help"
  )
  command_options_set_string="$(generate_set_options_string)"
  [[ "${command_options_set_string}" = '' ]] && command_options_set_string='<no_options_set>'

  for option_string in "${friendly_option_groupings[@]}"
  do
    group_option_count="$(echo "${option_string}" | egrep -o '[^ ]+' | wc -l)"
    unique_count="$(echo "${option_string} ${command_options_set_string}" | egrep -o '[^ ]+' | natsort | uniq | wc -l)"

    [[ "${unique_count}" -le "${group_option_count}" ]] && valid_option_combi_found=1 && break
  done

  if [[ "${valid_option_combi_found}" -eq 0 && "${command_options_set_string}" != '<no_options_set>' ]]; then
    echo -e "error: invalid parameter combination \n"
    usage
    exit 1
  fi
}

generate_set_options_string() {
  local result=''
  for option in "${!command_options_set[@]}"
  do
    [[ "${command_options_set[$option]}" -eq 1 ]] && result+="${option} "
  done
  echo "${result}"
}

auto_ports_option_handler() {
  echo -e "\n\033[1mAuto-detecting available ports...\033[0m"
  auto_find_ports_and_set_config_if_found

  if [[ "${auto_find_result}" = 'success' ]]; then
    echo -e "Detected available p2p_bind_port \t-> port ${config[p2p_bind_port]}"
    echo -e "Detected available rpc_bind_port \t-> port ${config[rpc_bind_port]}"
    echo -e "Detected available zmq_rpc_bind_port \t-> port ${config[zmq_rpc_bind_port]}"
  fi
}

inspect_auto_magic_option_handler() {
  ports_option_handler "auto"
  echo -e "\nIf needed you can alter and set these ports manually by:\n\n    \033[0;33mbash install.sh multi-node -m p2p:9330,rpc:9331,zmq:9332\033[0m\n"

  auto_search_available_username
  echo -e "\nIf needed you can alter and set the username manually by:\n\n    \033[0;33mbash install.sh multi-node -u mysnodeuser\033[0m"
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

user_option_handler() {
  if [[ "$1" = "auto" ]]; then
    auto_search_available_username
  else
    config[running_user]="$1"
  fi
}

ports_option_handler() {
  if [[ "$1" = "auto" ]]; then
    auto_ports_option_handler
  elif valid_manual_port_string_format "$1" ; then
    parse_manual_port_string_and_set_config_if_valid "$1"
  else
    echo -e "Invalid --manual-ports config format '$1'\n"
    usage
  fi
}

valid_manual_port_string_format() {
  [[ "$(echo "$1" | egrep -o -e "^[a-z2]{3}:[0-9]+,[a-z2]{3}:[0-9]+,[a-z2]{3}:[0-9]+$" | egrep -o -e "p2p:[0-9]+" -e "rpc:[0-9]+" -e "zmq:[0-9]+" | wc -l )" -eq 3 ]]
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

init() {
  [[ "${config[running_user]}" = "root" ]] && homedir='/root' || homedir="/home/${config[running_user]}"
  installer_home="${homedir}/eqnode_installer"

#  if ! [[ -f ~/.screenrc ]]; then
#    cp screenrc.conf ~/.screenrc
#  fi
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

scan_for_concurrent_install_sessions() {
  local pids pid_exec_path install_session_states home_user
  pids=( $(sudo ps aux | egrep '[b]ash.*eqsnode.sh' | gawk '{ print $2 }' | grep '[0-9]') )
  install_session_states=()

  for process_id in "${pids[@]}"
  do
    # surpress stderr of pwdx command (in case process is stopped), which would otherwise break the command
    pid_exec_path="$(sudo pwdx "${process_id}" 2> /dev/null | grep -o '/.*')"

    # empty when process stopped
    if [[ "${pid_exec_path}" != "" ]] && [[ -f "${pid_exec_path}/.installsessionstate" ]]; then
      home_user="$(echo "${pid_exec_path}" | grep -oP '/home/\K[^/]*')"
      install_session_states+=("${home_user};${process_id};$(cat "${pid_exec_path}/.installsessionstate");${pid_exec_path}")
    fi
  done

  # shellcheck disable=SC2086
  echo ${install_session_states[*]}
}

setup_running_user () {
  validate_running_user
  create_running_user_if_needed
  sudoers_running_user_nopasswd 'add'
}

validate_running_user() {
  echo -e "\n\033[1mValidating user '${config[running_user]}'...\033[0m"

  if running_user_has_active_daemon; then
    echo -e "\n\033[0;33mSAFETY POLICY VIOLATION: User '${config[running_user]}' is already running an active service node daemon. Please install with a different user!\033[0m"
    echo -e "\nIn case you want to install a second service node on this VPS or server, please use the following command instead:\n\n\033[0;33m    bash install.sh --multi-node\033[0m"
    echo -e "\nInstallation aborted."
    exit 1
  fi
}

running_user_has_active_daemon() {
   [[ "$(sudo ps aux | egrep '[b]in/daemon.*--service-node' | gawk '{ print $1 }' | natsort | uniq | grep -o "^${config[running_user]}$" | wc -l)" -gt 0 ]]
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

    echo -e "\n\033[1mA previous installation session for user '${config[running_user]}' has been detected with the following config:\033[0m"
    # Echo install.conf, while skipping #-comment lines
    cat "${installer_home}/install.conf" | egrep "^[^#].*"
    echo ""

    while true; do
      read -p 'Do you want to continue or overwrite this session? (or press ENTER to abort installation) [C/O]: ' co
      co=${co:-exit}

      case $co in
            [Cc]* )       break;;
            [Oo]* )       copy_installer_to_install_user_homedir
                          break;;
            quit | exit)  echo -e "\nInstallation aborted."; exit 0 ;;
            * )           echo -e "(Please answer C or O)";;
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
  create_install_session_screen_lifeline
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

bash $0 [OPTIONS...]

Options:
  -m  --multi-node            Shorthand for --user auto'. Setting --user will override this option
  -i  --inspect-auto-magic    Display preview of all automatically set port, user and Equilibria version
  -p  --ports [auto|config]   Manual port configuration; 'p2p:<port>,rpc:<port>,zmq:<port>'
                              Example:  --ports p2p:9330,rpc:9331,zmq:9332

                              Auto detect ports; This requires ALL other service nodes to be active!
                              Example:  --ports auto

  -u --user [auto|name]       Set username that will run the service node or 'auto' for autodetect
                              Example:  --user snode2
                                        --user auto

  -v --version [tag]          Set Equilibria version with format 'v0.0.0'
  --skip-prepare-sn           Skip the auto start of the prepare_sn command at the end
                              of the install

  -h  --help                  Show this help text

USAGEMSG
}

finally() {
  result=$?
  echo ""
  exit ${result}
}
trap finally EXIT ERR INT

main "${@}"
exit 0
