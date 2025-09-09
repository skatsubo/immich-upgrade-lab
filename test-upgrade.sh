#!/usr/bin/env bash

#
# shell
#
set -e

#
# configuration and constants
#
timeout_startup=120

# dir for running sandbox (ephemeral/test instance undergoing upgrade from baseline to target)
sandbox_dir='.'
# dir for everything else: managed baselines/snapshots/origins and compose release files. They are placed in corresponding subdirectories
cache_dir='.'
# use rsync instead of cp
use_rsync=true


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

# copy from source to destination dir
# a wrapper for cp / rsync
copy() {
    local src="$1"
    local dest="$2"
    shift 2
    local opts="$*"
    log "Copy from: $src to: $dest opts: ${opts:-none}"

    if [[ -n "$use_rsync" ]] ; then
        rsync -a $opts "$src"/ "$dest"
    else
        mkdir -p "$dest"
        cp -r "$src"/. "$dest"
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

# setup_dirs
ensure_paths() {
    # order of mkdir-vs-realpath matters because realpath on Macos does not have --canonicalize-missing "no path components need exist or be a directory"
    mkdir -p "$sandbox_dir"
    sandbox_dir_abs=$(realpath "$sandbox_dir")

    mkdir -p "$cache_dir"
    cache_dir_abs=$(realpath "$cache_dir")

    # script_dir=$(dirname $(realpath -f "$0"))

    snapshot_dir="$cache_dir_abs/snapshot/$from"
    snapshot_data_dir="$snapshot_dir/library"
    snapshot_postgres_dir="$snapshot_dir/postgres"

    release_dir="$cache_dir_abs/release/$from"

    sandbox_data_dir="$sandbox_dir_abs"/library
    sandbox_postgres_dir="$sandbox_dir_abs"/postgres
}

download_release_compose_files() {
    # TODO: unless exists
    local ver
    local release_dir
    for ver in "$@" ; do
        log "Get compose and env from Immich release $ver"

        release_dir="$cache_dir_abs/release/$ver"

        if [[ -f $release_dir/docker-compose.yml ]] && [[ -f $release_dir/.env ]] ; then
            log "Compose files for $ver already exist in $release_dir. Nothing to do."
        else
            mkdir -p "$release_dir"
            curl -sSL -o "$release_dir/docker-compose.yml" "https://github.com/immich-app/immich/releases/download/$ver/docker-compose.yml"
            curl -sSL -o "$release_dir/.env" "https://github.com/immich-app/immich/releases/download/$ver/example.env"
        fi
    done
}

determine_sandbox_sources() {
    # if
    #   no custom "from" source compose/data/postgres paths specified 
    # and 
    #   snapshot already exists at the default "./snapshot/$version" path
    # then use snapshot's content (copy its data/config when provisioning new sandbox)
    if [[ -z ${from_compose}${from_data}${from_postgres} ]] && check_snapshot_exists ; then
        source_type='snapshot'

        if [[ -z $from_compose_release ]]; then
            source_compose_dir="$snapshot_dir"
        else
            source_compose_dir="$release_dir"
        fi
        source_data_dir="$snapshot_dir/library"
        source_postgres_dir="$snapshot_dir/postgres"

        log "Snapshot exists in '$snapshot_dir', use it as a source when creating sandbox. (Remove the snapshot directory if you would like to start from scratch, then re-run this script)"
    else
        # when a directory is specified, use it
        # otherwise for compose use the release version, for data/postgres assume they need to be created from scratch
        if [[ -n ${from_data}${from_postgres} ]] ; then
            source_type='custom'
        else
            source_type='scratch'
        fi
        source_compose_dir="${from_compose:-$release_dir}"
        source_data_dir="${from_data:-}"
        source_postgres_dir="${from_postgres:-}"
    fi
    log "Snapshot source type: $source_type"
}

provision_sandbox_cleanup_compose() {
    # remove compose files
    find "$sandbox_dir" -type f -maxdepth 1 \( -name '*compose*.y*ml' -o -name '*.env' \) -delete
}

provision_sandbox_cleanup_data_postgres() {
    # remove data (library) and postgres
    rm -rf "$sandbox_data_dir"
    rm -rf "$sandbox_postgres_dir"
}

provision_sandbox_cleanup() {
    provision_sandbox_cleanup_compose
    provision_sandbox_cleanup_data_postgres
}

provision_sandbox_compose() {
    local ver="$1"
    local source_dir="$2"
    local dest_dir="$3"

    log "Provision compose and env files from: $source_dir"

    copy "$source_dir" "$dest_dir" --include='*compose*.y*ml' --include='*.env' --exclude='*'

    echo "IMMICH_VERSION=$ver" >> "$dest_dir"/.env
}

# copy_content between dirs
provision_sandbox_content() {
    local content="$1"
    local source_dir="$2"
    local dest_dir="$3"
    shift 3
    local opts="$*"
    log "Provision $content from: $source_dir"

    copy "$source_dir" "$dest_dir" $opts
}

# provision sandbox from sources (if any) or use empty/default
provision_sandbox() {
    log "Provision sandbox from: $source_type"

    # clean up when from "scratch", destructive operation
    # exclude "custom" and "snapshot" from cleanup as a perf optimization:
    # in case there is large volume of data to be copied, especially over network
    # TODO: handle "custom" and "snapshot" to avoid accumulating garbage, e.g. rsync --delete
    provision_sandbox_cleanup_compose
    if [[ $source_type == "scratch" ]]; then
        provision_sandbox_cleanup_data_postgres
    fi

    # compose
    provision_sandbox_compose "$from" "$source_compose_dir" "$sandbox_dir"

    # data
    if [[ -n $source_data_dir ]]; then
        provision_sandbox_content data "$source_data_dir" "$sandbox_data_dir" "$from_data_opts"
    else
        log "Provision empty data dir"
    fi

    # postgres
    if [[ -n $source_postgres_dir ]]; then
        provision_sandbox_content postgres "$source_postgres_dir" "$sandbox_postgres_dir"
    else
        log "Provision empty postgres dir"
    fi

    deploy_stack
}

# TODO: handling of $source_type to make code DRY
# TODO: use determine_sandbox_sources()
provision_sandbox_from_snapshot() {
    source_type="snapshot"

    if [[ -z $from_compose_release ]]; then
        source_compose_dir="$snapshot_dir"
    else
        source_compose_dir="$release_dir"
    fi
    source_data_dir="$snapshot_dir/library"
    source_postgres_dir="$snapshot_dir/postgres"

    provision_sandbox
}

deploy_stack() {
    log "These docker images will be used:"
    docker compose config | grep "image:"
        # Expected output includes current version to be upgraded from
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
    if [[ -f docker-compose.yml ]] || [[ -f compose.yaml ]]; then
        docker compose down
    fi
    provision_sandbox_cleanup
}

setup_sandbox_initial () {
    # heredoc is indented with tabs (not spaces) to match code indentation
    local msg=$(cat <<-'EOF'
		This setup will be used as a baseline/snapshot for upgrades.
		Go to http://localhost:2283 and do initial configuration, upload photos, check if it looks good.
		EOF
    )
    wait_for_user "$msg"
}

# internal baseline exists
check_snapshot_exists() {
    # if [[ -d "$ver"/postgres ]] && [[ -d "$ver"/library ]] && [[ -f "$ver"/.env ]] && [[ -f "$ver"/docker-compose.yml ]] ; then
    if [[ -f "$snapshot_dir/state.ok" ]]; then
        return 0
    fi
    return 1
}

make_snapshot() {
    # stop, backup
    log "Create snapshot"
    docker compose stop

    # TODO: better handling, do not overwrite in certain scenarios
    if check_snapshot_exists ; then
        log "Snapshot at $snapshot_dir exists. Overwriting."
    fi

    mkdir -p "$snapshot_dir"

    # TODO: cleanup before copying ?
    copy "$sandbox_data_dir" "$snapshot_data_dir"
    copy "$sandbox_postgres_dir" "$snapshot_postgres_dir"
    copy "$sandbox_dir" "$snapshot_dir" --include='*compose*.y*ml' --include='*.env' --exclude='*'

    touch "$snapshot_dir/state.ok"
}

wait_for_immich_running() {
    log "Wait for Immich to become ready"

    local container="immich_server"
    local is_healthy=''
    for i in $(seq 1 $((timeout_startup/2))); do
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container")
        if [[ $status == "healthy" ]]; then
            debug "Container is healthy."
            is_healthy="true"
            break
        else
            printf "."
        fi
        sleep 2
    done
    if [[ -n $is_healthy ]]; then
        echo ok
    else
        echo 
        log "WARN: container $container is not healthy after $timeout_startup sec. Check sandbox's logs and retry. Also this may be a bug in the script. Exiting."
    fi
}

#
# command line functions
#
cli_print_help() {
    echo
    echo "Immich upgrade in a sandbox"
    echo
    echo "Performs upgrade from version ver1 to version ver2 in a sandbox."
    echo "It tests two upgrade scenarios: (1) new version + old compose, (2) new version + new compose."
    echo
    echo "The test instance (sandbox) can be created:"
    echo "  - from scratch (empty) using default/release compose"
    echo "  - from a previously created snapshot"
    echo "  - using existing Immich instance's compose+data+postgres"
    echo "By default, when no optional args are specified, the sandbox is created from this version's snapshot if exists, otherwise from scratch."
    echo
    echo "Both versions (from and to) are mandatory arguments."
    echo
    echo "Usage:"
    echo "  $0 <ver1> <ver2>                   # Upgrade from version1 to version2"
    echo "  $0 --from <ver1> --to <ver2>       # Upgrade from version1 to version2 (flags form)"
    echo "  $0 <ver1> <ver2> [--args ...]      # Upgrade with extra args"
    echo "  $0 --help                          # Show this help"
    echo
    echo "Optional arguments:"
    echo "  --from-compose <dir>    Use compose files from specified location when creating sandbox."
    echo "  --from-data <dir>       Use (copy) Immich data (library) from specified location when creating sandbox."
    echo "  --from-data-opts <opts> Filter applied when copying existing Immich data (library). Passed verbatim to rsync."
    echo "  --from-postgres <dir>   Use (copy) Postgres data from specified location when creating sandbox."
    # echo "  --from-compose-release  [WIP] Force using release compose files for sandbox even if compose files are present in the source (snapshot or custom)."
    # echo "                          By default release files are used only when creating a fresh sandbox from scratch or when missing in source."
    # echo "  --from-dir <...>        [WIP] Create sandbox by copying existing data (library, postgres) from <dir>."
    echo
    echo "Examples:"
    echo "  $0 v1.123.0 v1.132.3"
    echo "  $0 --from v1.123.0 --to v1.132.3"
    echo
}

parse_args() {
    debug "args:" "$@" "| num args: $#"

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --from)            from="$2"; from_version="$2"; shift 2 ;;
            --from-compose)    from_compose="$2"; shift 2 ;;
            --from-compose-release) from_compose_release=1; shift ;;
            --from-data)       from_data="$2" ; shift 2 ;;
            --from-data-opts)  from_data_opts="$2" ; shift 2 ;;
            --from-postgres)   from_postgres="$2" ; shift 2 ;;
            --to)              to="$2"; to_version="$2" ; shift 2 ;;
            --help|-h)         cli_print_help; exit 0 ;;
            *)                 from="$1"; to="$2" ; shift 2 ;;
        esac
    done

    if [[ -z "$from" || -z "$to" ]]; then
        echo "Both versions 'from' and 'to' are required."
        cli_print_help
        exit 1
    fi
}

#
# variables
#

# mainly for logging
ver=''

snapshot_dir=''

# sandbox source type: scratch (fresh, empty data and postgres), snapshot, custom (external, provided path)
source_type="scratch"

#
# main
#
parse_args "$@"
log "Testing upgrade: $from -> $to"
warn

# set dir/path variables, resolve/canonicalize, create dirs if not exist
# this must be done before "cd anywhere" because args may contain relative paths
ver="$from"
ensure_paths

# use sandbox dir as the current/work dir for all following tasks/functions
# for now assume current working dir is the sandbox dir
# TODO: support "cd anywhere"
# cd "$sandbox_dir"

ver=''
log "Get compose+env for requested versions. You can review/compare them."
download_release_compose_files "$from" "$to"

# prepare sandbox
ver="$from"
determine_sandbox_sources
log "Setting up a sandbox $ver to be tested for upgrades. Sandbox data will be populated from: $source_type."
if docker compose config >/dev/null 2>&1 ; then
  teardown
fi
provision_sandbox
setup_sandbox_initial
make_snapshot
teardown

# upgrade path 1: "from" -> "to" using compose of "from"
ver="$from"
echo
log "🟡"
log "🟡 [Test 1] Upgrade to $to using the existing/current docker-compose.yml (matching $from)"
log "🟡"
provision_sandbox_from_snapshot
wait_for_immich_running

ver="$to"
log "Begin upgrade. Set target IMMICH_VERSION=$ver, but keep the existing compose of the current version $from"
echo "IMMICH_VERSION=$ver" >> "$sandbox_dir"/.env
deploy_stack
wait_for_user "Upgrade to $to done. Verify it: upload photos, check logs for errors."
teardown

# upgrade path 2: "from" -> "to" using compose of "to"
ver="$from"
echo
log "🟡"
log "🟡 [Test 2] Upgrade to $to using docker-compose.yml for the target version (released in $to)"
log "🟡"
provision_sandbox_from_snapshot
wait_for_immich_running

ver="$to"
log "Begin upgrade. Use compose of the target version (released in $to)"
provision_sandbox_compose "$to" "$release_dir" "$sandbox_dir"
deploy_stack
wait_for_user "Upgrade to $to done. Verify it: upload photos, check logs for errors."
teardown
