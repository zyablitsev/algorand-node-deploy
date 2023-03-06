# Algorand Node Deploy Automating Script

Script for automating deployment of your own [Algorand MainNet non-archive Node](https://developer.algorand.org/docs/run-a-node/setup/types/) to send transactions and read current state of smart contracts/applications.

### Usage

**Limitations: Debian 11 (bullseye)**

**IMPORTANT:** The script will install an [Algorand](https://www.algorand.com) node and configure [NFTables](https://netfilter.org/projects/nftables/), you will be asked for IP address to be added to the trusted list to access algod, kmd and ssh services, the ip address of the current ssh session will be used by default.

Open terminal and run:
```bash
~$ apt-get install -y ca-certificates curl
~$ bash <(curl -s "https://raw.githubusercontent.com/zyablitsev/algorand-node-deploy/main/install.sh")
```

Check your node status:
```bash
~$ ALGORAND_DATA=/opt/algorand/node/data /opt/algorand/node/goal node status
```
