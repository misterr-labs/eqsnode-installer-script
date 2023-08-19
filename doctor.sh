#!/usr/bin/env bash
# by Mister R

set -o errexit
set -o nounset
set -o pipefail

script_basedir=$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")
readonly script_basedir

source "${script_basedir}/discovery.sh"

eqnode_doctor_version='v1.0.0'
readonly eqnode_doctor_version

typeset -A doctor_config
doctor_config=(
  [fix_mode]='interactive'
)

typeset -A command_options_set
command_options_set=(
  [help]=0
  [auto_fix]=0
)


main() {
  install_dependencies
  print_splash_screen
  process_command_line_args "$@"

  analyze_and_fix
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
  echo -e "Service node doctor script ${eqnode_doctor_version}\n"
}

install_dependencies() {
  if ! [[ -x "$(command -v netstat)" && -x "$(command -v openssl)" && -x "$(command -v natsort)" && -x "$(command -v grep)" && -x "$(command -v getopt)" && -x "$(command -v gawk)" ]]; then
    echo -e "\n\033[1mFixing required dependencies....\033[0m"
    sudo apt -y install net-tools openssl python3-natsort grep util-linux gawk
  fi
}

process_command_line_args() {
  parse_command_line_args "$@"
  validate_parsed_command_line_args
  set_config_and_execute_info_commands
}

parse_command_line_args() {
  args="$(getopt -a -n installer -o "hf" --long help,auto-fix -- "$@")"
  eval set -- "${args}"

  while :
  do
    case "$1" in
      -h | --help)                  command_options_set[help]=1 ; shift ;;
      -f | --auto-fix)              command_options_set[auto_fix]=1; shift ;;
      --)                           shift ; break ;;
      *)                            echo "Unexpected option: $1" ;
                                    usage
                                    exit 0 ;;
    esac
  done
}

validate_parsed_command_line_args() {
  local friendly_option_groupings group_option_count command_options_set_string unique_count valid_option_combi_found
  valid_option_combi_found=0

  friendly_option_groupings=(
    "<no_options_set>"
    "auto_fix"
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
    echo -e "\033[0;33merror: Invalid parameter combination\033[0m\n"
    usage
    exit 1
  fi
}

set_config_and_execute_info_commands() {
  [[ "${command_options_set[help]}" -eq 1 ]] && usage && exit 0
  [[ "${command_options_set[auto_fix]}" -eq 1 ]] && auto_fix_mode_option_handler

  # necessary return 0
  return 0
}

generate_set_options_string() {
  local result=''
  for option in "${!command_options_set[@]}"
  do
    [[ "${command_options_set[$option]}" -eq 1 ]] && result+="${option} "
  done
  echo "${result}"
}

auto_fix_mode_option_handler() {
  doctor_config[fix_mode]='auto'
}

analyze_and_fix() {
  declare -A daemon_users
  echo -e "\n\033[1mAnalyzing active service nodes...\033[0m"

  discover_daemons daemon_users 'user'
  local node_blockstate
  local allowed_block_difference=2
  local blocks_done= ; local total_blocks= ;

  echo -e "\n\033[1mFetching external blockchain state...\033[0m"
  local current_block="$(wget --quiet https://explorer.equilibriacc.com/ -O - | grep -o 'Equilibria emission is .* as of .* block' | sed -n 's/^Equilibria emission is \([0-9]*\)\.\([0-9]*\) as of \([0-9]*\).*/\3/p')"
  echo -e "Blockchain explorer current block: ${current_block}"

  local current_block_with_margin=$((current_block - allowed_block_difference));
  declare -A healthy_blockchains='()'
  declare -A bad_blockchains='()'
  local badidx=1
  local healthyidx=1

  for username in "${daemon_users[@]}"
  do
    echo -e "\n\033[1mChecking health of service node ran by user '${username}'...\033[0m"

    read blocks_done total_blocks perc <<< "$(sudo -H -u ${username} bash -c 'cd ~/eqnode_installer/ && bash eqsnode.sh status' | grep -o 'Height:.*' | sed -n 's/^Height: \([0-9]*\)\/\([0-9]*\) (\([0-9.]*\).*/\1 \2 \3/p')"

    echo "Local blockchain at block: ${blocks_done}"

    if [[ "${perc}" = "100.0" && "${blocks_done}" -lt "${current_block_with_margin}" ]]; then
      bad_blockchains["$badidx"]="${username}"
      badidx=$((badidx + 1))
      echo "Blockchain state: BAD"
    else
      healthy_blockchains["$healthyidx"]="${username}"
      healthyidx=$((healthyidx + 1))
      echo "Blockchain state: HEALTHY"
    fi
  done
  if [[ "${#bad_blockchains[@]}" -gt 0 ]]; then

    if [[ "${#healthy_blockchains[@]}" -gt 0 ]]; then
      if [[ "${doctor_config[fix_mode]}" = "interactive" ]]; then
        while true; do
          read -p $'\n\033[1mThere are bad blockchains. Do you want to fix them?\e[0m [Y/N]: ' yn
          yn=${yn:-N}

          case $yn in
                [Yy]* ) break;;
                [Nn]* ) exit 1;;
                * ) echo -e "(Please answer Y or N)";;
          esac
        done
      fi
      local username_badblockchain
      local bad_blockchain_dir healthy_blockchain_dir
      for username_badblockchain in "${bad_blockchains[@]}"
      do
        echo -e "\n\033[1mFixing blockchain of user '${username_badblockchain}'...\033[0m"
        echo -e "Stopping service node daemon..."
        sudo -H -u "${username_badblockchain}" bash -c 'cd ~/eqnode_installer/ && bash eqsnode.sh stop'

        bad_blockchain_dir="/home/${username_badblockchain}/.equilibria"
        healthy_blockchain_dir="/home/${healthy_blockchains[1]}/.equilibria"

        echo -e "\nReplacing bad blockchain by a healthy donor blockchain...(may take several minutes)"
        sudo rm -Rf "${bad_blockchain_dir}"
        sudo mkdir "${bad_blockchain_dir}"
        sudo chmod "$(stat --format '%a' "${healthy_blockchain_dir}")" "${bad_blockchain_dir}"
        sudo cp -R "${healthy_blockchain_dir}/lmdb" "${bad_blockchain_dir}"
        sudo chown -R "${username_badblockchain}":"${username_badblockchain}" "${bad_blockchain_dir}"


        echo -e "Starting service node daemon..."
        sudo -H -u "${username_badblockchain}" bash -c 'cd ~/eqnode_installer/ && bash eqsnode.sh start'
      done

      echo -e "\n\033[1mDone\033[0m"
    else
      echo -e "\n\033[1mUnable to perform surgery as no healthy donor blockchains were found.\e[0m"
      exit 0
    fi
  else
    echo -e "\n\033[1mHealth check OK\e[0m"
  fi
#  no donor service nocde found

}

usage() {
  cat <<USAGEMSG

bash $0 [OPTIONS...]

Options:
  -f --auto-fix                         Scans for "corrupted" blockchains of active service
                                        nodes and will attempt to fix it without user interaction

  -h  --help                            Show this help text

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

