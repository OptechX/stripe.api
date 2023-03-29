#!/usr/bin/env bash

# disable docker compose (if it's running)
docker compose down

# remove docker networks and clean up images
docker network prune --force
docker rm $(docker ps -aq) --force
docker rmi $(docker images -aq) --force

# create networks
docker network create web
docker network create --internal internal

# restart docker services
docker compose up -d

