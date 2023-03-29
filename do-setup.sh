#!/usr/bin/env bash

## SET HOSTNAME
base_uri="$SSH_URI"
hostnamectl set-hostname $base_uri

## SET DATE/TIME
timedatectl set-timezone Australia/Sydney
timedatectl set-ntp true

## BYPASS AUTO CONFIG
export DEBIAN_FRONTEND=noninteractive
cat >> /etc/apt/apt.conf.d/sshd-config-keep <<EOF
Dpkg::Options {
   "--force-confdef";
   "--force-confold";
}
EOF

## UPDATE APT
apt-get update

## INSTALL DOCKER
apt-get -y install ca-certificates curl gnupg
mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
chmod a+r /etc/apt/keyrings/docker.gpg
apt-get update
apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

## INSTALL/CONFIG UFW FOR DOCKER
apt -y install ufw
cat >> /etc/ufw/after.rules <<EOF
# BEGIN UFW AND DOCKER
*filter
:ufw-user-forward - [0:0]
:ufw-docker-logging-deny - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -j ufw-user-forward
-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16
-A DOCKER-USER -p udp -m udp --sport 53 --dport 1024:65535 -j RETURN
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 172.16.0.0/12
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 172.16.0.0/12
-A DOCKER-USER -j RETURN
-A ufw-docker-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW DOCKER BLOCK] "
-A ufw-docker-logging-deny -j DROP
COMMIT
# END UFW AND DOCKER
EOF
systemctl restart ufw

## ADD ADMIN ACCOUNT
useradd -m $SSH_USER
adminrpcpass=$(cat /proc/sys/kernel/random/uuid | head -c 36; echo;)
echo -e "$adminrpcpass\n$adminrpcpass" | passwd $SSH_USER
usermod -aG sudo $SSH_USER
usermod -aG docker $SSH_USER
if ! which rsync; then
  apt -y install rsync
fi
rsync --archive --chown=$SSH_USER:$SSH_USER ~/.ssh /home/$SSH_USER
chsh -s /usr/bin/bash $SSH_USER
echo $adminrpcpass > /home/$SSH_USER/default_password
usermod -aG sudo $SSH_USER

## UPDATE PKGS
apt update
apt -y upgrade

## CONFIGURE SSHD
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords no/' /etc/ssh/sshd_config
echo "AllowUsers $SSH_USER" >> /etc/ssh/sshd_config

## ENABLE UFW PORTS
ufw route allow proto tcp from any to any port 5432
ufw route allow proto tcp from any to any port 10000
ufw route allow proto tcp from any to any port 80
ufw route allow proto tcp from any to any port 443
ufw allow ssh
echo -e 'y' | ufw enable

## INSTALL TREE
apt -y install tree

## AUTHORIZED KEYS FOR GITHUB
echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCttM5fgfo820du5mOPaoYTpPR08P185P7et2neLyz6lESh9YQFD0agBEWE6Uh2W8ZbgF4VpspoQPOlQEpVQujdTRSmitA7CVLe0uQheZXG3ggYvB2jreHeJpohw2vFk1V+XEiY+FbxYobFjEKpBwRfaxFQUVia0dBLhSz8qI3v7u9kKW3wiFMsV+CdC6JalV50k7MdDZt2U0EoAagxB+m8S8er4+kvgmM7t0MMaz/tzqiNCaK0VTdYchkLYRGoDylJICacEjhX6ynHImyzK7mFLQ34Z5Sl+fNPgaE/ZsON9V827Nf4ENVRBL59Mh2bnjdtXMhFYevg2NE0JAHhY/xA9rNii2tIEsg0vlqjMZ4abQIELZRcc0UF+fZgH65qWlZtX46b7hNLMynW5EEXPR5dxfbSISECbuvygqFl4xTc1YVBcUyBAnccO/PKxc9WKM5Xc+O5xpsXh6XITRYizuvqyW50XDnexTeGP7j74lrvrNi0Bm1XqCt29V8Ya8OmwRbpBApq9NcGej7IUpfZE1jHF/63+fantZTCOhPWnKuhBQKDaFC7mwe2GfJigl8kUk3uTBuTn93vGVKwDyGTnxY2NvqiEBUlHy6k4U3OAPyfUwA1wzQZ1QdCOoe+Hkpt6iT70/5AbzwvFgv5MZmwIQmRhdJQZJEaHNJwy4rpa9dbQw== user@host' >> /home/$SSH_USER/.ssh/authorized_keys

## RESTART SSHD
systemctl reload sshd

## CREATE DOCKER PRE-REQS
docker network create web
docker network create --internal internal
mkdir -p /data/caddy/config
mkdir -p /data/caddy/data
mkdir -p /data/nginx

## REBOOT MACHINE
reboot
