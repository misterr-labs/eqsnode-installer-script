# Equilibria service node easy setup guide

## Pull this script from Github (as root)
#### As root? Yes, but do not worry! While the script needs to be run as root, the script will automatically create users that will run the service node(s).
```
cd ~
sudo apt -y install git
git clone https://github.com/misterr-labs/eqsnode-installer-script
cd eqsnode-installer-script
```
#### Already pulled this script from Github before? Update it to the latest version:
```
cd ~/eqsnode-installer-script
git pull --force
```

## Installation of a service node
`bash install.sh --open-firewall`

#### It is recommended to install or upgrade with the option `--open-firewall` which will open the P2P in/out ports so the node can interact with other service nodes. 

#### While not required it is recommended to inspect the auto-magic behind the scenes first.

`bash install.sh -i`

## Multi service node installation (one VPS or server)

#### Install multiple nodes with just one command:

`bash install.sh --nodes 2 --open-firewall`
#### Suggestion: have a look at the --one-passwd-file option in the Advanced features section

#### Note: while not required it is recommended to inspect the auto-magic behind the scenes first, to double check if everything looks good.
`bash install.sh --nodes 2 -i`
<br />
## Build in help for install.sh and upgrade.sh
#### Run the following to get a list of commands you can use:
`bash install.sh --help`

`bash upgrade.sh --help`

## Upgrading a service node
#### For example to upgrade nodes ran by users `snode` and `snode2` to the latest officially released version:
`bash upgrade.sh --user snode,snode2`

#### Or a more advanced version:
`bash upgrade.sh --user snode,snode2 --open-firewall --set-daemon-log-level 0,stacktrace:FATAL`



## Advanced features

### To install a node with a specific username. 
#### (note: the auto-ports feature is enabled by default)

`bash install.sh --user mysnode10`

### Install multi-nodes with specific usernames and manual ports configs
`bash install.sh --nodes 2 --user mysnode1,mysnode2 --ports p2p:9330+9430,rpc:9331+9431`

#### Or use the shorthand version
`bash install.sh -n 2 -u mysnode1,mysnode2 -p p2p:9330+9430,rpc:9331+9431`

### Install a node using a copy af a specific blockchain
#### While an existing blockchain is attempted to be auto-detected, it is possible that it will not detect a blockchain when there is one, or perhaps you want to specify a specific blockchain to use.
`bash install.sh --copy-blockchain /home/snode/.equilibria`

#### Or if you want a fresh blockchain download for each installed node
`bash install.sh --copy-blockchain no`

#### Or first node a fresh blockchain download, while the remaining nodes to install a copy of the first
`bash install.sh --nodes 3 --copy-blockchain no,auto`

#### Note: using '--copy-blockchain no' will dramatically increase the installation time when installing multiple nodes

### Some other highlighted options:
#### OPTION: `--set-daemon-log-level` which allows you to control the log level of the daemon to log less or more information. 
`bash install.sh --nodes 3 --set-daemon-log-level 0,stacktrace:FATAL`

#### OPTION: `--version` installs/upgrades to a specific version, by version tag, 'master' branch or git hash code. For example:
`bash install.sh --nodes 3 --version v20.1.1`

`bash install.sh --nodes 3 --version 122d5f6a6`

#### Omitting the `--version` option will install the latest officially released version (latest version tag).

### Avoid repeated manual password input for service node users
#### In case you install multiple nodes with the --nodes option, it can be annoying to input password and re-passwords many times. To avoid this, use below command to set one password a single time and all newly created service node users will use this one password (stored encrypted).

`bash install.sh --one-passwd-file`

#### After the .onepasswd file is created you can start an installation like usual. You will not be prompted to enter passwords during the installation.
#### Note: Future installations will also use this .onepasswd file. In case you want to type in passwords manually again, please remove this file:

`rm ~/eqsnode-installer-script/.onepasswd`

<br /><br />


