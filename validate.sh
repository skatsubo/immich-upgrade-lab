#!/usr/bin/env bash

# exit on errors
set -e

log() {
    echo "${FUNCNAME[1]}" "[$ver]" "$@"
}

warn() {
    echo "======================================================"
    echo "⚠️ Run this script from a dedicated empty directory. ⚠️"
    echo "⚠️ Data inside this directory will be destroyed.     ⚠️"
    echo "======================================================"
}

wait_for_user() {
    echo "================================================"
    echo -e "$*"
    echo
    echo "Press any key to continue when done..."
    echo "================================================"
    echo ""
    read -n 1 -s -r
}

download_compose_files() {
    for ver in "$@" ; do
        log "Get compose and env from Immich release assets"
        mkdir -p "release/$ver"
        curl -sSL -o "release/$ver/docker-compose.yml" "https://github.com/immich-app/immich/releases/download/$ver/docker-compose.yml"
        curl -sSL -o "release/$ver/.env" "https://github.com/immich-app/immich/releases/download/$ver/example.env"
    done
    ver=""
}

provision_compose_files() {
    log "Provision compose and env files"
    cp "release/$ver/docker-compose.yml" "release/$ver/.env" .
    echo "IMMICH_VERSION=$ver" >> .env
}

deploy_stack() {
    log "These images will be used:"
    docker compose config | grep "image:"
        # Expected output includes current/baseline version to be upgraded from
        # image: docker.io/tensorchord/pgvecto-rs:pg14-v0.2.0@sha256:90724186f0a3517cf6914295b5ab410db9ce23190a2d9d0b9dd6463e3fa298f0
        # image: ghcr.io/immich-app/immich-machine-learning:v1.123.0
        # image: ghcr.io/immich-app/immich-server:v1.123.0
        # image: docker.io/redis:6.2-alpine@sha256:eaba718fecd1196d88533de7ba49bf903ad33664a92debb24660a922ecd9cac8

    log "Deploy the stack"
    docker compose pull -q
    docker compose up -d
}

teardown() {
    log "Teardown: remove stack, configs, data (if present)"
    # "down" without "-v" to keep the named volume of ML model cache - to avod re-downloading model files and make testing faster
    [ -f docker-compose.yml ] && docker compose down
    rm -rf ./library ./postgres .env docker-compose.yml docker-compose.override.yml
}

setup_baseline_initial () {
    # on baseline version: do initial setup, upload a few photos and so on
    wait_for_user "This setup will be used as baseline / initial version for upgrades.\nGo to http://localhost:2283 and do initial configuration, upload photos, check if it looks good."

    # stop, backup, destroy the baseline
    log "Create backup"
    docker compose stop
    mkdir -p "$ver"
    cp -r ./library ./postgres .env docker-compose.yml "$ver"

    teardown
}

check_backup_exists() {
    if [[ -d "$ver"/postgres ]] && [[ -d "$ver"/library ]] && [[ -f "$ver"/.env ]] && [[ -f "$ver"/docker-compose.yml ]] ; then
        return 0
    fi
    return 1
}

provision_from_backup() {
    log "Provision stack from backup"
    log "Restore configs and data directories (library, postgres)"
    rm -rf ./library ./postgres .env docker-compose.yml docker-compose.override.yml
    cp -r "$ver"/* "$ver"/.env .

    deploy_stack
}

wait_for_immich_running() {
    log "Wait for Immich to become ready"
    container="immich_server"
    for i in $(seq 1 $((timeout/2))); do
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container")
        if [[ $status == "healthy" ]]; then
            echo "Container is healthy."
            break
        else
            printf "."
        fi
        sleep 2
    done
}

#
# variables
#

ver123=v1.123.0
ver132=v1.132.3
ver136=v1.136.0
ver=""

timeout=120

#
# main
#

warn

log "Get compose+env for all versions. You can review/compare them."
download_compose_files $ver123 $ver132 $ver136



# prepare baseline
ver="$ver123"
teardown
log "Setting up baseline version $ver to be tested for upgrades"
if ! check_backup_exists ; then
    log "Install and configure baseline"
    provision_compose_files
    deploy_stack
    setup_baseline_initial
else
    log "Backup exists in '$ver', use it as baseline. (Remove '$ver' directory if you would like to start from scratch, then re-run this script)"
fi



# upgrade path 123 -> 132
from_ver="$ver123" ; to_ver="$ver132"

ver="$from_ver"
log "🟡"
log "🟡 [Test v132] Upgrade to $to_ver using existing/old docker-compose.yml (released in $from_ver)"
log "🟡"
provision_from_backup
wait_for_immich_running
ver="$to_ver"
log "Set IMMICH_VERSION=$ver"
echo "IMMICH_VERSION=$ver" >> .env
deploy_stack
wait_for_user "Upgrade to $to_ver done. Verify it: upload photos, check logs for errors."
teardown



# upgrade path 123 -> 136
from_ver="$ver123" ; to_ver="$ver136"

ver="$from_ver"
log "🟡"
log "🟡 [Test 1 v136] Upgrade to $to_ver using existing/old docker-compose.yml (released in $from_ver)"
log "🟡"
provision_from_backup
wait_for_immich_running
ver="$to_ver"
log "Set IMMICH_VERSION=$ver"
echo "IMMICH_VERSION=$ver" >> .env
deploy_stack
wait_for_user "Upgrade to $to_ver done. Verify it: upload photos, check logs for errors."
teardown



ver="$from_ver"
log "🟡"
log "🟡 [Test 2 v136] Upgrade to $to_ver using docker-compose.yml for this release (released in $to_ver)"
log "🟡"
provision_from_backup
wait_for_immich_running
ver="$to_ver"
provision_compose_files
deploy_stack
wait_for_user "Upgrade to $to_ver done. Verify it: upload photos, check logs for errors."
teardown
