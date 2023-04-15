# Equilibria service node easy setup guide

## Download this script from Github
`git clone https://github.com/misterr-labs/eqsnode-installer-script`

`cd eqsnode-installer-script`

## Installation of single service node
#### Note: run root user (or sudo user)

`bash install.sh`
-
## Out-of-the-box multi service node installation on one VPS or server
#### Note: run root user (or sudo user)

### To preview the auto-magic port and username detection (not required)
`bash install.sh multi-node --preview-auto-magic`

#### Or use the shorthand version
`bash install.sh multi-node -p`

### To install multiple nodes on one VPS or server
`bash install.sh multi-node`
-
## Customized multi service node installation on one VPS or server

### To install an additional nodes on one VPS or server with specific username. Will use auto-ports feature by default.
`bash install.sh multi-node --username mysnode10`

#### Or use the shorthand version
`bash install.sh multi-node -u mysnode10`

### To install an additional nodes on one VPS or server with specific username and manual ports config
`bash install.sh multi-node --username mysnode10 --manual-ports p2p:10330,rpc:10331,zmq:10332`
#### Or use the shorthand version
`bash install.sh multi-node -u mysnode10 -m p2p:10330,rpc:10331,zmq:10332`

## After install (NOT A REQUIRED STEP)

### Run the following to get a list of commands you can use
`bash eqsnode.sh --help`
