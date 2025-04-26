#!/bin/bash
SERVER_PUB_IP=$(curl -s httpbin.org/ip|grep origin|cut -d '"' -f 4)
SERVER_PUB_NIC="enX0"
SERVER_WG_NIC="wg0"
SERVER_WG_IPV4=$(ip -4 addr  show $SERVER_PUB_NIC| grep -oP '(?<=inet\s)\d+(\.\d+){3}')
SERVER_WG_IPV6="fd42:42:42::1"
SERVER_PORT=54332
CLIENT_DNS_1="1.1.1.1"
CLIENT_DNS_2="8.8.8.8"
ALLOWED_IPS="10.0.6.0/24"
function install() {
apt-get update
apt-get install -y wireguard iptables resolvconf qrencode wireguard-tools

mkdir /etc/wireguard >/dev/null 2>&1
chmod 600 -R /etc/wireguard/

SERVER_PRIV_KEY=$(wg genkey)
SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)

echo "SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${SERVER_WG_NIC}
SERVER_WG_IPV4=${SERVER_WG_IPV4}
SERVER_WG_IPV6=${SERVER_WG_IPV6}
SERVER_PORT=${SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}
ALLOWED_IPS=${ALLOWED_IPS}" >/etc/wireguard/params


echo "[Interface]
Address = ${SERVER_WG_IPV4}/24,${SERVER_WG_IPV6}/64
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}" >"/etc/wireguard/${SERVER_WG_NIC}.conf"

echo "PostUp = iptables -I INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT
PostUp = iptables -I FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PostUp = iptables -I FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostUp = ip6tables -I FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT
PostDown = iptables -D FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PostDown = iptables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = ip6tables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostDown = ip6tables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"

echo "net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1" >/etc/sysctl.d/wg.conf
sysctl --system

systemctl start "wg-quick@${SERVER_WG_NIC}"
systemctl enable "wg-quick@${SERVER_WG_NIC}"
}

function unInstall() {
	systemctl stop "wg-quick@${SERVER_WG_NIC}"
	systemctl disable "wg-quick@${SERVER_WG_NIC}"
	sysctl --system
	rm -rf /etc/wireguard
	rm -f /etc/sysctl.d/wg.conf
	systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"
	echo $?
}
function newClient(){
ENDPOINT="${SERVER_PUB_IP}:${SERVER_PORT}"
DOT_IP=$1
CLIENT_WG_IPV4="${SERVER_WG_IPV4::-1}${DOT_IP}"
CLIENT_NAME="client${DOT_IP}"
CLIENT_PRIV_KEY=$(wg genkey)
CLIENT_PUB_KEY=$(echo "${CLIENT_PRIV_KEY}" | wg pubkey)
CLIENT_PRE_SHARED_KEY=$(wg genpsk)
SERVER_PUB_KEY=$(cat /etc/wireguard/params|grep SERVER_PUB_KEY|sed 's/SERVER_PUB_KEY=//g')
echo "[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_WG_IPV4}/32
DNS = ${CLIENT_DNS_1},${CLIENT_DNS_2}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
Endpoint = ${ENDPOINT}
AllowedIPs = ${ALLOWED_IPS}" >"/root/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

# Add the client as a peer to the server
echo -e "\n### Client ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"

wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}")
}


case "$1" in
  install)
    install # calling function start()
    ;;
  uninstall)
    unInstall # calling function stop()
    ;;
  newclient)
    for i in $(seq 10 60);
    do
       newClient $i # calling function stop()
    done
    ;;
  *)
    echo "Usage: $0 {start|stop|restart}" >&2

     exit 1
     ;;
esac
