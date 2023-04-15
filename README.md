# Equilibria service node easy setup guide

## Download this script from Github (in homedir)
`cd ~`

`git clone https://github.com/misterr-labs/eqsnode-installer-script`

`cd eqsnode-installer-script`

## Installation of a single service node (first node on VPS or server)
#### Note: run root user (or sudo user)

`bash install.sh`
-
<br />

## Multi service node installation (one VPS or server)
#### Note: run root user (or sudo user)

`bash install.sh multi-node`
-
<br />

### Preview auto-magic (not a required step)
`bash install.sh multi-node --preview-auto-magic`
-
<br />

#### Or use the shorthand version

`bash install.sh multi-node -p`

## Build in help
`bash install.sh --help`
-

<br />

## Advanced 'multi-node' features

### To install a 'multi-node' with a specific username. Auto-ports feature is enabled by default.
`bash install.sh multi-node --username mysnode10`

#### Or use the shorthand version
`bash install.sh multi-node -u mysnode10`

### To install a 'multi-node' with specific username and manual ports config
`bash install.sh multi-node --username mysnode10 --manual-ports p2p:10330,rpc:10331,zmq:10332`

#### Or use the shorthand version
`bash install.sh multi-node -u mysnode10 -m p2p:10330,rpc:10331,zmq:10332`

## After install (NOT A REQUIRED STEP)

### Run the following to get a list of commands you can use
`bash eqsnode.sh --help`
