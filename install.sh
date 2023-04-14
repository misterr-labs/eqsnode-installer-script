#!/usr/bin/env bash
# by Mister R

set -o errexit
set -o nounset
set -o pipefail

script_basedir=$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")
readonly script_basedir

source "${script_basedir}/common.sh"

installer_home=

main() {
  init
  print_splash_screen
  install_checks
  setup_running_user
  copy_installer_or_continue_session
  install_with_running_user
  finish_install
}

init() {
  [[ "${config[running_user]}" = "root" ]] && homedir='/root' || homedir="/home/${config[running_user]}"
  installer_home="${homedir}/eqnode_installer"
}

print_splash_screen () {
  cat <<'SPLASHMSG'

 _________            .__.__  ._____.         .__
 |  _____/ ________ __|__|  | |__|_ |_________|__|____
 |   ___/_/ ____/  |  \  |  | |  || __ \_  __ \  \__  \
 |  |___ < <_|  |  |  /  |  |_|  || \_\ \  | \/  |/ __ \_
 |_______/\__   |____/|__|____/__||_____/__|  |__(______/
             |__|

SPLASHMSG
echo -e "Service node installer script ${eqnode_installer_version}\n"
}

install_checks () {
  echo -e "\\033[1mExecuting pre-install checks...\033[0m"
  inspect_time_services
}

inspect_time_services () {
  echo -e "\033[1mChecking clock NTP synchronisation...\033[0m"

  if  [[ -x "$(command -v timedatectl)" ]]; then
    if [[ $(sudo timedatectl | grep -o -e 'synchronized: yes' -e 'service: active' | wc -l) -ne 2 ]]; then
      echo -e "\n\033[0;33mERROR: Clock NTP synchronisation is not working correctly. This is required to run a stable service node. Please fix 'timedatectl' before continuing.\033[0m\n"
      timedatectl
      exit 1
    fi
  else
    echo -e "\033[0;33mWARNING: Clock sync could not be verified.\nPlease check and make sure this is working before continuing!\033[0m\n"
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

setup_running_user () {
  create_running_user_if_needed
  sudoers_running_user_nopasswd 'add'
}

create_running_user_if_needed() {
   # shellcheck disable=SC2154
   if ! id -u "${config[running_user]}" >/dev/null 2>&1; then
     echo -e "\033[0;33mFor the service node we need to create a user '${config[running_user]}'. You will be asked to enter a password for this user next. Please make sure to keep this password safe.\033[0m\n"
     read -n 1 -s -r -p "Press ANY key to continue"

     echo -e "\n\033[1mCreating sudo user '${config[running_user]}'\033[0m"
     sudo adduser --gecos GECOS "${config[running_user]}"
     sudo usermod -aG sudo "${config[running_user]}"
   fi
}

sudoers_running_user_nopasswd() {
  local action="$1"
  local sudo_settings
  [[ "${action}" = 'add' ]] && sudo_settings='ALL=(ALL) NOPASSWD:ALL' || sudo_settings='ALL=(ALL:ALL) ALL'
  # shellcheck disable=SC2116
  local sed_command="$(echo "/^${config[running_user]} /{h;s/ .*/ ${sudo_settings}/};\${x;/^$/{s//${config[running_user]} ${sudo_settings}/;H};x}")"
  sudo sed -i "${sed_command}" /etc/sudoers
}

copy_installer_or_continue_session() {
  if [[ -d "${installer_home}" ]]; then
    if [[ -f "${installer_home}/.installsessionstate" ]] && [[ "$(cat "${installer_home}/.installsessionstate")" = "${installer_state[finished_eqsnode_install]}" ]]; then
      echo -e "\033[0;33mA finished installation of an Equilibria service node has been found! This installation script is ONLY for fresh installations not for updating a service node.\033[0m"
    fi

    while true; do
      read -p 'A previous installation session has been detected! Do you want to continue this session? (press ENTER to for: yes) [Y/N]: ' yn
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
  sudo cp eqsnode.sh eqnode.service.template install.conf common.sh "${installer_home}"
  sudo chown -R "${config[running_user]}":root "${installer_home}"
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

finally() {
  result=$?
  echo ""
  exit ${result}
}
trap finally EXIT ERR INT

main "${@}"
