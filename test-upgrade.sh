#!/usr/bin/env bash

#
# shell
#
set -e

#
# configuration and constants
#
timeout_startup=120

#
# aux functions
#
log() {
    echo "${FUNCNAME[1]}" "[$ver]" "$@"
}

err() {
    echo "Error: $*" >&2
}

debug() {
    if [[ -n "$DEBUG" ]] ; then
        echo "debug:" "${FUNCNAME[1]}:" "$@"
    fi
}

#
# upgrade functions
#
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
    wait_for_user "This setup will be used as a baseline / initial version for upgrades.\nGo to http://localhost:2283 and do initial configuration, upload photos, check if it looks good."

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
    for i in $(seq 1 $((timeout_startup/2))); do
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
# command line functions
#
cli_print_help() {
    echo "Immich upgrade in a sandbox"
    echo
    echo "Performs upgrade from version ver1 to version ver2 in a sandbox."
    echo "It tests two scenarios: (1) new version + old compose, (2) new version + new compose."
    echo
    echo "Usage:"
    echo "  $0 <ver1> <ver2>                # Test upgrades from version1 to version2"
    echo "  $0 --from <ver1> --to <ver2>    # Test upgrades from version1 to version2 (flags form)"
    echo "  $0 --help                       # Show this help"
    echo
    echo "Example:"
    echo "  $0 v1.123.0 v1.132.3"
    echo "  $0 --from v1.123.0 --to v1.132.3"
    echo
}

parse_args() {
    debug "args:" "$@" "| num args: $#"

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --from)    from="$2"; shift 2 ;;
            --to)      to="$2"; shift 2 ;;
            --help|-h) cli_print_help; exit 0 ;;
            *)         from="$1"; to="$2"; break ;;
        esac
    done

    if [[ -z "$from" || -z "$to" ]]; then
        cli_print_help
        exit 1
    fi
}

#
# variables
#
ver=""

#
# main
#
parse_args "$@"

log "Testing upgrade: $from -> $to"

warn

log "Get compose+env for requested versions. You can review/compare them."
download_compose_files $from $to

# prepare baseline
ver="$from"
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

# upgrade path 1: "from" -> "to" using compose of "from"
ver="$from"
echo
log "🟡"
log "🟡 [Test 1] Upgrade to $to using the existing/current docker-compose.yml (released in $from)"
log "🟡"
provision_from_backup
wait_for_immich_running

ver="$to"
log "Set target IMMICH_VERSION=$ver, but keep the existing compose of the current version $from"
echo "IMMICH_VERSION=$ver" >> .env
deploy_stack
wait_for_user "Upgrade to $to done. Verify it: upload photos, check logs for errors."
teardown

# upgrade path 2: "from" -> "to" using compose of "to"
ver="$from"
echo
log "🟡"
log "🟡 [Test 2] Upgrade to $to using docker-compose.yml for the target version (released in $to)"
log "🟡"
provision_from_backup
wait_for_immich_running

ver="$to"
log "Use compose for the target version"
provision_compose_files
deploy_stack
wait_for_user "Upgrade to $to done. Verify it: upload photos, check logs for errors."
teardown
