# Equilibria service node easy setup guide

## Pull this script from Github (as root)
#### As root? Yes, but do not worry! While the script needs to be run as root, the script will automatically create users that will run the service node(s).
```
cd ~
sudo apt -y install git
git clone https://github.com/misterr-labs/eqsnode-installer-script
cd eqsnode-installer-script
```

## Installation of a service node
`bash install.sh`


#### While not required it is recommended to inspect the auto-magic behind the scenes first.

`bash install.sh -i`

## Multi service node installation (one VPS or server)

#### Install multiple nodes with just one command:

`bash install.sh --nodes 2`
#### Suggestion: have a look at the --one-passwd-file option in the Advanced features section

#### Note: while not required it is recommended to inspect the auto-magic behind the scenes first, to double check if everything looks good.
`bash install.sh --nodes 2 -i`
<br />
## Build in help
#### Run the following to get a list of commands you can use:
`bash install.sh --help`

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

#### or if you want a fresh blockchain download for each installed node
`bash install.sh --copy-blockchain no`

#### Note: usign '--copy-blockchain no' will dramatically increase the installation time when installing multiple nodes

### Avoid repeated manual password input for service node users
#### In case you install multiple nodes with the --nodes option, it can be annoying to input password and re-passwords many times. To avoid this, use below command to set one password a single time and all newly created service node users will use this one password (stored encrypted).

`bash install.sh --one-passwd-file`

#### After the .onepasswd file is created you can start an installation like usual. You will not be prompted to enter passwords during the installation.
#### Note: Future installations will also use this .onepasswd file. In case you want to type in passwords manually again, please remove this file:

`rm ~/eqsnode-installer-script/.onepasswd`

<br /><br />


