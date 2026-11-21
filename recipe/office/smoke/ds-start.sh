#!/usr/bin/env bash
# Dentro do container do DS: aplica a trava de egress (so loopback + rede docker privada), depois roda os servicos como uid 1000.
set -eu
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
iptables -A OUTPUT -d 10.0.0.0/8 -j ACCEPT
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-port-unreachable
iptables -nvL OUTPUT > /var/log/onlyoffice/iptables.start.txt
exec setpriv --reuid=1000 --regid=1000 --clear-groups bash /run-services.sh
