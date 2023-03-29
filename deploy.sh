#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

ssh -o "StrictHostKeyChecking=no" "$SSH_USER@$SSH_URL" 'rm -rf docker-compose.yml'

scp -o "StrictHostKeyChecking=no" -rp "$SCRIPT_DIR/lib/data" "$SSH_USER@$SSH_URL:/"
scp -o "StrictHostKeyChecking=no" -rp "$SCRIPT_DIR/lib/home/$SSH_USER/" "$SSH_USER@$SSH_URL:/home/$SSH_USER/"
ssh -o "StrictHostKeyChecking=no" "$SSH_USER@$SSH_URL" 'find /data -name "*.gitkeep" -type f -print0 | xargs -0 /bin/rm -f'

ssh -o "StrictHostKeyChecking=no" "$SSH_USER@$SSH_URL" 'docker compose down; docker network prune --force; docker network create web; docker network create --internal internal; docker rmi $(docker images -aq) --force; docker compose up -d'