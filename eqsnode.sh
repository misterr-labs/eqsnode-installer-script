#! /bin/env bash
# v1.0 developed by GreggyGB
# v2.0 by Mister R
# v3.0 by Mister R

set -o errexit
set -o nounset
set -o pipefail

script_basedir=$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")
install_root_bin_dir=$(echo ~)
install_root_service='/etc/systemd/system'
readonly script_basedir install_root_bin_dir install_root_service

source "${script_basedir}/common.sh"

service_name="eqnode_${config[running_user]}.service"
service_file="${install_root_service}/${service_name}"
readonly service_name service_file

port_params=
if ! default_ports_configured; then
  port_params="--zmq-rpc-bind-port ${config[zmq_rpc_bind_port]} --p2p-bind-port ${config[p2p_bind_port]} --rpc-bind-port ${config[rpc_bind_port]}"
fi
readonly port_params

active_user=${USER:=$(/usr/bin/id -run)}
readonly active_user

service_template="${script_basedir}/eqnode.service.template"
readonly service_template

daemon_start_time=

main() {
  case "$1" in
    install )       install_node ;;
    prepare_sn )    prepare_sn ;;
    start )         start ;;
    stop )          stop_all_nodes ;;
    status )        status ;;
    log )           log ;;
    update )        update ;;
    fakerun )       sleep 300 ;;
#    fork_update ) fork_update ;;
    print_sn_key )  print_sn_key ;;
    * ) usage
  esac
}

install_node() {
  init
  install_manager
}

init() {
  if [ "${config[running_user]}" != "${active_user}" ]; then
    printf "\033[0;31mFATAL\033[0m: Wrong user running '%s'. Expected user: '%s'. Current user: '%s'!\n" "${BASH_SOURCE[0]}" "${config[running_user]}" "${active_user}"
    echo -e "Please run this script with the correct user or modify 'install.conf'.\n"

    if [ "${active_user}" = 'root' ]; then
      echo -e "\033[0;33mIn case you simply need to quickly install the Equilibria service node. Please run below command as root user instead, especially if you have not used this command for this install before\033[0m:\n\tbash install.sh\n"
    fi
    exit 1
  fi

  if ! [[ -f "${installer_session_state_file}" ]]; then
    set_install_session_state "${installer_state[started]}"
  fi
}

install_manager() {
  local current_install_state="$(read_install_session_state)"

  if [ "${current_install_state}" != "${installer_state[started]}" ]; then
    echo -e "Skipping ahead to previous exit point...\n"
  fi

  # ';&' fall-through case, based on installer_session_state_file.
  case "${current_install_state}" in
    "${installer_state[started]}")            ;&
    "${installer_state[install_packages]}")   install_required_packages ;&
    "${installer_state[checkout_git]}")       checkout_git_repo ;&
    "${installer_state[compile_move]}")       compile_and_move_binaries ;&
    "${installer_state[install_service]}")    build_and_install_service_file ;&
    "${installer_state[enable_service]}")     enable_service_on_boot ;&
    "${installer_state[start_service]}")      start_service ;&
    "${installer_state[watch_daemon]}")       watch_daemon_status ;&
    "${installer_state[ask_prepare]}")        ask_prepare_sn ;&
    "${installer_state[finished]}")           finish_eqsnode_install ;;
    *) printf "Unknown installer state '%s' found in '%s'. Aborting..." "${current_install_state}" "${installer_session_state_file}"
       exit 1 ;;
  esac
}

install_required_packages() {
  set_install_session_state "${installer_state[install_packages]}"

  echo -e "\n\033[1mInstalling tool packages...\033[0m"
  sudo apt -y install wget unzip git
  sudo apt update
#  ln -s /usr/local/lib/python3.8/dist-packages/cmake /usr/bin/cmake
#https://apt.kitware.com/

  sudo apt-get -y install bc build-essential cmake pkg-config libboost-all-dev libssl-dev libzmq3-dev libunbound-dev libsodium-dev libunwind8-dev liblzma-dev libreadline6-dev libldns-dev libexpat1-dev doxygen graphviz libpgm-dev qttools5-dev-tools libhidapi-dev libusb-dev libprotobuf-dev protobuf-compiler
}

checkout_git_repo() {
  set_install_session_state "${installer_state[checkout_git]}"

  if [ "${config[install_version]}" = 'auto' ]; then
    echo -e "\033[1mRetrieving latest version tag from Github...\033[0m"
    config[install_version]="$(git ls-remote --tags "${config[git_repository]}" | grep -o 'v.*' | sort -V | tail -1)"
  fi
  echo -e "\n\033[1mChecking Out Equilibra Repository Files...\033[0m"
  git clone --recursive "${config[git_repository]}" equilibria && cd equilibria
  git submodule init && git submodule update
  git checkout "${config[install_version]}"
}

compile_and_move_binaries() {
  set_install_session_state "${installer_state[compile_move]}"

  echo -e "\n\033[1mCompiling Equilibria binaries...\033[0m"
  make

  echo -e "\n\033[1mMoving Equilibria binaries to installation directory...\033[0m"
  cd build/Linux/_HEAD_detached_at_"${config[install_version]}"_/release && mv bin "${install_root_bin_dir}"
}

build_and_install_service_file() {
  set_install_session_state "${installer_state[install_service]}"

  if [[ -f "${service_file}" ]]; then
    echo -e "\n\033[1mRemoving existing '${service_file}' file...\033[0m"
    sudo rm "${service_file}"
  fi

  echo -e "\n\033[1mGenerating service file '${service_file}'...\033[0m"

  # shellcheck disable=SC2002
  cat "${service_template}" | sed -e "s/%INSTALL_USERNAME%/${config[running_user]}/g" -e "s#%INSTALL_ROOT%#${install_root_bin_dir}#g" -e "s/%PORT_PARAMS%/${port_params}/g" | sudo tee "${service_file}"

  echo -e "\n\033[1mReloading service manager...\033[0m"
  sudo systemctl daemon-reload
}

enable_service_on_boot() {
  set_install_session_state "${installer_state[enable_service]}"

  echo -e "\n\033[1mEnabling service to start automatically upon boot...\033[0m"
  sudo systemctl enable "${service_name}"
}

start_service() {
  set_install_session_state "${installer_state[start_service]}"
  daemon_start_time=$(date +%s)
  start
}

wait_daemon_start() {
   sleep 10
   local timeout_time=30
   local polling_time_passed=0

   while [ $polling_time_passed -lt $timeout_time ]; do
     sleep 1
     if ps aux | grep -q "[d]aemon --non-interactive --service-node" ; then
       break
     fi
     (polling_time_passed=$polling_time_passed+1)

     if [[ $polling_time_passed -eq $timeout_time ]]; then
       echo -e "\033[0;31mOops, the Equilibria daemon seems to be not started or crashed.\033[0m\nExiting service node installer\n"
       exit 1
     fi
   done
}

watch_daemon_status() {
  set_install_session_state "${installer_state[watch_daemon]}"

  echo -e "\n\033[1mWaiting till daemon is detected...\033[0m"
  wait_daemon_start

  local start_time=${daemon_start_time}
  local start_block=0
  local estimate_time_remaining='Estimating time remaining...'
  local blocks_done= ; local total_blocks= ; local perc=
  local delta_blocks_done=$((blocks_done-start_block))
  local blocks_per_sec=
  local blocks_remaining=
  local sec_left_till_completion=
  local hours_left= ; local mins_left=
  local hour_word= ; local min_word=
  local current_time=
  local delta_time=

  echo -e "\n\033[1mMonitoring blockchain download progress by daemon:\033[0m"
  setterm -cursor off

  while true; do
    read blocks_done total_blocks perc <<< "$(~/bin/daemon status ${port_params} | grep -o 'Height:.*' | sed -n 's/^Height: \([0-9]*\)\/\([0-9]*\) (\([0-9.]*\).*/\1 \2 \3/p')"

    # skip output of odd total number of blocks like 0 or 1
    [[ "${total_blocks}" -lt 1000 ]] && continue

    current_time=$(date +%s)
    delta_time=$((current_time - start_time))

    # calculate new ETR every 60 sec
    if [[ $delta_time -ge 60 ]]; then
      delta_blocks_done=$((blocks_done-start_block))
      blocks_per_sec=$(bc -l <<< "($delta_blocks_done/$delta_time)")
      blocks_remaining=$((total_blocks - blocks_done))
      sec_left_till_completion=$(bc <<< "($blocks_remaining/$blocks_per_sec)")
      hours_left=$((sec_left_till_completion/3600))
      mins_left=$((sec_left_till_completion%3600/60))
      [[ $hours_left -eq 1 ]] && hour_word='hour' || hour_word='hours'
      [[ $mins_left -eq 1 ]] && min_word='minute' || min_word='minutes'
      estimate_time_remaining=$(printf "ETR: ~ %d %s and %d %s left @ %d blocks p/min" "$hours_left" "$hour_word" "$mins_left" "$min_word" "$delta_blocks_done")
      start_time=$current_time
      start_block=$blocks_done
    fi

    printf "\r\t(%.01f%%) - %d/%d (%s)%-18s" "${perc}" "${blocks_done}" "${total_blocks}" "${estimate_time_remaining}" ""

    if [[ $blocks_done -eq $total_blocks ]]; then
      echo -e "\n"
      set_install_session_state "${installer_state[ask_prepare]}"
      break
    fi
    sleep 10 # sleep for 10 seconds
  done
  setterm -cursor on
}

ask_prepare_sn() {
  if [[ "${config[skip_prepare_sn]}" -eq 0 ]]; then
    while true; do
      read -p $'\033[1mDo you want to prepare the Service Node (prepare_sn)?\e[0m (press ENTER for: Yes) [Y/N]: ' yn
      yn=${yn:-Y}

        case $yn in
              [Yy]* ) prepare_sn
                      break;;
              [Nn]* )
                      echo -e "Note: you can prepare the Service Node by running the following command manually:\n\tbash ${script_basedir}/eqsnode.sh prepare_sn"
                      exit 1;;
              * ) echo -e "(Please answer Y or N)";;
        esac
    done
  fi
}

finish_eqsnode_install() {
  set_install_session_state "${installer_state[finished_eqsnode_install]}"
}

prepare_sn() {
  ~/bin/daemon prepare_sn ${port_params}
}

start() {
  sudo systemctl start "${service_name}"
  echo "Service node started to check it works use bash equilibria.sh log"
}

status() {
  ~/bin/daemon status ${port_params}
  #systemctl status "${service_name}"
}

stop_all_nodes() {
  echo Stopping XEQ node
  sudo systemctl stop "${service_name}"
}

log() {
  sudo journalctl -u "${service_name}" -af
}

update() {
  git pull
}

print_sn_key() {
  ~/bin/daemon print_sn_key ${port_params}
}

#fork_update() {
#  rm -Rf "${script_basedir}/equilibria"
#  git clone --recursive "${config[git_repository]}" equilibria && cd equilibria
#  git submodule init && git submodule update
#  git checkout "${config[install_version]}"
#  make
#  sudo systemctl stop "${service_name}"
#  rm -r ~/bin
#  cd build/Linux/_HEAD_detached_at_"${config[install_version]}"_/release && mv bin ~/
#  sudo systemctl enable "${service_name}"
#  sudo systemctl start "${service_name}"
#}

usage() {
  cat <<USAGEMSG
bash $0 [COMMAND...] [OPTION...]

Commands:
  install             Install of Equilibria service node
  start               Start Equilibria service node
  stop                Stop Equilibria service node
  prepare_sn          Prepare Equilibria service node for staking
  print_sn_key        Print service node key
  status              Check service status
  log                 View service log

Options:
  -?  -h  --help      Show this help text

USAGEMSG
}

usage_help_is_needed() {
  [[ ( "${#}" -ge "1" && ( "$1" = '-h' || "$1" = '--help' || "$1" = '-?' )) || "${#}" -eq "0" ]]
}

finally() {
  result=$?
  setterm -cursor on
  echo ""
  exit ${result}
}
trap finally EXIT ERR INT

if usage_help_is_needed "$@"; then
  usage
  exit 0
fi

main "${@}"
