#!/bin/bash

set -eu

v_program="${0##*/}"
v_self="$(readlink -f "${BASH_SOURCE[0]}")"
[[ $UID == 0 ]] || exec sudo -p "$v_program must be run as root. Please enter the password for %u to continue: " -- "$BASH" -- "$v_self"

v_trust_ip="`last -1w | grep $USER | awk '{ print $3 }'`"
v_ssh_port="`cat /etc/ssh/sshd_config 2>/dev/null | grep Port | awk '{ print $2 }' | head -n 1`"

read -p "Enter IP to allow ssh,algod,kmd access (default '$v_trust_ip'): " -i $v_trust_ip -e v_trust_ip

# Run the commands in a noninteractive mode
export DEBIAN_FRONTEND=noninteractive

# update system packages
apt-get update -y
apt-get upgrade -y

# install required system packages
apt-get install -y ca-certificates curl nftables

# configure nftables
cat <<EOF > /etc/nftables.conf
table ip filter {
        set trust_ipset {
                type ipv4_addr
                elements = { $v_trust_ip }
        }

        chain input {
                type filter hook input priority filter; policy drop;
                iifname "lo" accept
                iifname != "lo" ip saddr 127.0.0.0/24 reject with icmp type prot-unreachable
                iifname "eth0" ip protocol icmp ct state { established, related } accept
                iifname "eth0" udp sport 53 ct state established accept
                iifname "eth0" tcp sport 53 ct state established accept
                iifname "eth0" tcp sport { 80, 443 } ct state established accept
                iifname "eth0" icmp type echo-request ip saddr @trust_ipset ct state new accept
                iifname "eth0" tcp dport { $v_ssh_port, 9090, 9091, 9100 } ip saddr @trust_ipset ct state { established, new } accept
        }

        chain output {
                type filter hook output priority filter; policy drop;
                oifname "lo" accept
                oifname "eth0" ip protocol icmp ct state { established, new } accept
                oifname "eth0" udp dport 53 ct state { established, new } accept
                oifname "eth0" tcp dport 53 ct state { established, new } accept
                oifname "eth0" tcp dport { 80, 443 } ct state { established, new } accept
                oifname "eth0" tcp sport { $v_ssh_port, 9090, 9091, 9100 } ip daddr @trust_ipset ct state established accept
        }
}
EOF

systemctl enable nftables.service
systemctl start nftables.service

# create algorand user
useradd --system \
    -M \
    --user-group \
    --shell /sbin/nologin \
    algorand

# install algorand node
mkdir -p /opt/algorand/node
curl -L -o /opt/algorand/node/update.sh \
    https://raw.githubusercontent.com/algorand/go-algorand-doc/master/downloads/installers/update.sh

chmod 500 /opt/algorand/node/update.sh

cd /opt/algorand/node/ \
    && ./update.sh -i -n -c stable \
        -p /opt/algorand/node/ \
        -d /opt/algorand/node/data/

# configure algod
cat <<EOF > /opt/algorand/node/data/config.json
{
  "Archival": false,
  "CatchupBlockDownloadRetryAttempts": 100000,
  "DNSBootstrapID": "<network>.algorand.network",
  "DNSSecurityFlags": 1,
  "EnableDeveloperAPI": true,
  "EnableMetricReporting": true,
  "EndpointAddress": ":9090",
  "FallbackDNSResolverAddress": "8.8.8.8",
  "GossipFanout": 8,
  "NodeExporterListenAddress": ":9100",
  "NodeExporterPath": "./node_exporter --no-collector.diskstats"
}
EOF

chown root:root /opt/algorand/node/data/config.json
chmod 0644 /opt/algorand/node/data/config.json

cat <<EOF > /opt/algorand/node/data/algod.token
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EOF

chown root:root /opt/algorand/node/data/algod.token
chmod 0644 /opt/algorand/node/data/algod.token

cat <<EOF > /opt/algorand/node/data/algod.admin.token
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EOF

chown root:root /opt/algorand/node/data/algod.admin.token
chmod 0644 /opt/algorand/node/data/algod.admin.token

# configure kmd
cat <<EOF > /opt/algorand/node/data/kmd-v0.5/kmd_config.json
{
  "address":":9091",
  "allowed_origins": ["*"],
  "session_lifetime_secs": 60
}
EOF

chown root:root /opt/algorand/node/data/kmd-v0.5/kmd_config.json
chmod 0644 /opt/algorand/node/data/kmd-v0.5/kmd_config.json

cat <<EOF > /opt/algorand/node/data/kmd-v0.5/kmd.token
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EOF

chown root:root /opt/algorand/node/data/kmd-v0.5/kmd.token
chmod 0644 /opt/algorand/node/data/kmd-v0.5/kmd.token

chown -R algorand:algorand /opt/algorand
chmod 700 /opt/algorand/node/data/kmd-v0.5

# configure systemd
cat <<EOF > /etc/default/algod
ALGORAND_DATA="/opt/algorand/node/data"
EOF

chown root:root /etc/default/algod
chmod 0644 /etc/default/algod

cat <<EOF > /lib/systemd/system/algod.service
[Unit]
Description=Algorand daemon under /opt/algorand/node/data
Wants=network.target
After=network.target
AssertFileIsExecutable=/opt/algorand/node/algod
AssertPathExists=/opt/algorand/node/data

[Service]
WorkingDirectory=/opt/algorand/node/

User=algorand
Group=algorand

EnvironmentFile=/etc/default/algod

ExecStartPre=bash -c "[[ ! -f /opt/algorand/node/data/system.json ]] && echo '{\"shared_server\":true,\"systemd_managed\":true}' > /opt/algorand/node/data/system.json || :"
ExecStart=/opt/algorand/node/algod

# Let systemd restart this service always
Restart=always
RestartSec=5s
ProtectSystem=false

# Specifies the maximum file descriptor number that can be opened by this process
LimitNOFILE=65536

# Disable timeout logic and wait until process is stopped
TimeoutStopSec=infinity
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF

chown root:root /lib/systemd/system/algod.service
chmod 0644 /lib/systemd/system/algod.service

systemctl enable algod
systemctl start algod

timeout 30 bash -c 'until printf "" 2>>/dev/null >>/dev/tcp/$0/$1; do sleep 1; done' 127.0.0.1 9090

catchpoint=$(curl "https://algorand-catchpoints.s3.us-east-2.amazonaws.com/channel/mainnet/latest.catchpoint")
ALGORAND_DATA=/opt/algorand/node/data /opt/algorand/node/goal node catchup "${catchpoint}"
ALGORAND_DATA=/opt/algorand/node/data /opt/algorand/node/goal node status
