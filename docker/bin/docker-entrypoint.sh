#!/usr/bin/env bash
set -Eeuo pipefail

log() {
	printf '%s\n' "docker-entrypoint: $*"
}

warn() {
	printf '%s\n' "docker-entrypoint: warning: $*" >&2
}

die() {
	printf '%s\n' "docker-entrypoint: error: $*" >&2
	exit 1
}

read_secret_value() {
	local name="$1"
	local file_name="${name}_FILE"
	local value="${!name:-}"
	local file="${!file_name:-}"

	if [ -n "$file" ]; then
		[ -r "$file" ] || die "${file_name} points to an unreadable file: ${file}"
		if [ -n "$value" ]; then
			warn "both ${name} and ${file_name} are set; using ${file_name}"
		fi
		head -n 1 "$file"
		return 0
	fi

	printf '%s' "$value"
}

resolve_env() {
	local target="$1"
	local default_value="$2"
	shift 2

	local name
	local value

	for name in "$target" "$@"; do
		value="$(read_secret_value "$name")"
		if [ -n "$value" ]; then
			export "$target=$value"
			return 0
		fi
	done

	export "$target=$default_value"
}

require_env() {
	local name="$1"

	if [ -z "${!name:-}" ]; then
		die "${name} is required; set ${name} or ${name}_FILE"
	fi
}

wait_for_database() {
	: "${GLPI_DB_WAIT_TIMEOUT:=60}"

	log "waiting for ${GLPI_DB_TYPE} at ${GLPI_DB_HOST}:${GLPI_DB_PORT}/${GLPI_DB_NAME}"

	local start
	start="$(date +%s)"

	while true; do
		case "${GLPI_DB_TYPE}" in
			mysql|mysqli|mariadb)
				if command -v mysqladmin >/dev/null 2>&1 && mysqladmin ping \
					--host="${GLPI_DB_HOST}" \
					--port="${GLPI_DB_PORT}" \
					--user="${GLPI_DB_USER}" \
					--password="${GLPI_DB_PASSWORD}" \
					--silent >/dev/null 2>&1; then
					log "database is ready"
					return 0
				fi
				;;
			pgsql|postgres|postgresql)
				if command -v pg_isready >/dev/null 2>&1 && PGPASSWORD="${GLPI_DB_PASSWORD}" pg_isready \
					-h "${GLPI_DB_HOST}" \
					-p "${GLPI_DB_PORT}" \
					-U "${GLPI_DB_USER}" \
					-d "${GLPI_DB_NAME}" >/dev/null 2>&1; then
					log "database is ready"
					return 0
				fi
				;;
			*)
				die "unsupported GLPI_DB_TYPE=${GLPI_DB_TYPE}; use mysql/mariadb for GLPI 10"
				;;
		esac

		if ! command -v mysqladmin >/dev/null 2>&1 && ! command -v pg_isready >/dev/null 2>&1; then
			warn "no database readiness client is installed; skipping readiness probe"
			return 0
		fi

		if [ "$(( $(date +%s) - start ))" -ge "$GLPI_DB_WAIT_TIMEOUT" ]; then
			die "database did not become ready within ${GLPI_DB_WAIT_TIMEOUT}s"
		fi

		sleep 2
	done
}

ensure_dir() {
	local dir="$1"
	local mode="${2:-0775}"
	local owner="${GLPI_RUNTIME_UID:-10001}:${GLPI_RUNTIME_GID:-0}"

	if [ "$(id -u)" = "0" ]; then
		mkdir -p "$dir"
		chown -R "$owner" "$dir"
		chmod -R u+rwX,g+rwX "$dir"
		return 0
	fi

	if [ -d "$dir" ]; then
		[ -w "$dir" ] || die "${dir} is not writable by uid $(id -u); start once as root or fix volume ownership to uid ${GLPI_RUNTIME_UID:-10001}"
		return 0
	fi

	if mkdir -p "$dir" 2>/dev/null; then
		chmod "$mode" "$dir" 2>/dev/null || true
		return 0
	fi

	die "cannot create ${dir} as uid $(id -u); start once as root or pre-create it with uid ${GLPI_RUNTIME_UID:-10001}"
}

ensure_permissions() {
	: "${GLPI_ROOT:=/var/www/html}"
	: "${GLPI_CONFIG_DIR:=/var/lib/glpi/config}"
	: "${GLPI_VAR_DIR:=/var/lib/glpi/files}"
	: "${GLPI_MARKETPLACE_DIR:=/var/lib/glpi/marketplace}"
	: "${GLPI_PLUGINS_DIR:=/var/lib/glpi/plugins}"
	: "${GLPI_LOG_DIR:=${GLPI_VAR_DIR}/_log}"

	log "checking GLPI volume permissions"

	ensure_dir "$GLPI_CONFIG_DIR"
	ensure_dir "$GLPI_VAR_DIR"
	ensure_dir "$GLPI_MARKETPLACE_DIR"
	ensure_dir "$GLPI_PLUGINS_DIR"
	ensure_dir "$GLPI_LOG_DIR"

	for subdir in _cache _cron _dumps _graphs _lock _pictures _plugins _rss _sessions _tmp _uploads; do
		ensure_dir "${GLPI_VAR_DIR}/${subdir}"
	done

	export GLPI_ROOT GLPI_CONFIG_DIR GLPI_VAR_DIR GLPI_MARKETPLACE_DIR GLPI_PLUGINS_DIR GLPI_LOG_DIR
}

configure_php_runtime() {
	local ini_dir="${GLPI_PHP_INI_DIR:-/var/lib/glpi/php-conf.d}"
	local ini_file="${ini_dir}/zz-glpi-runtime.ini"
	local memory_limit="${PHP_MEMORY_LIMIT:-512M}"
	local max_upload="${PHP_MAX_UPLOAD:-128M}"
	local max_execution_time="${PHP_MAX_EXECUTION_TIME:-300}"
	local timezone="${GLPI_TIMEZONE:-America/Bahia}"

	ensure_dir "$ini_dir" 0775
	cat >"$ini_file" <<EOF
memory_limit = ${memory_limit}
upload_max_filesize = ${max_upload}
post_max_size = ${max_upload}
max_execution_time = ${max_execution_time}
date.timezone = ${timezone}
EOF
	log "rendered PHP runtime limits"
}

run_setup() {
	local setup_script="${GLPI_SETUP_SCRIPT:-/usr/local/bin/glpi-setup.sh}"

	if [ ! -x "$setup_script" ]; then
		setup_script="$(dirname "$0")/glpi-setup.sh"
	fi

	[ -x "$setup_script" ] || die "setup script is not executable: ${setup_script}"
	"$setup_script"
}

start_cron() {
	if [ "${GLPI_START_CRON:-1}" = "0" ]; then
		log "cron startup disabled"
		return 0
	fi

	if [ "$(id -u)" != "0" ]; then
		(
			while true; do
				php "${GLPI_ROOT:-/var/www/html}/front/cron.php" --force || true
				sleep "${GLPI_CRON_INTERVAL:-60}"
			done
		) &
		log "GLPI cron loop started as uid $(id -u)"
		return 0
	fi

	if command -v service >/dev/null 2>&1; then
		if service cron start >/dev/null 2>&1 || service crond start >/dev/null 2>&1; then
			log "cron started via service manager"
			return 0
		fi
	fi

	if command -v cron >/dev/null 2>&1; then
		if cron; then
			log "cron started"
			return 0
		fi
	fi

	if command -v crond >/dev/null 2>&1; then
		if crond -b; then
			log "crond started"
			return 0
		fi
	fi

	warn "cron could not be started; container images running as uid 10001 may need cron prepared by the image or disabled with GLPI_START_CRON=0"
}

apache_command() {
	if command -v apache2-foreground >/dev/null 2>&1; then
		printf '%s\n' "apache2-foreground"
	elif command -v httpd-foreground >/dev/null 2>&1; then
		printf '%s\n' "httpd-foreground"
	elif command -v apache2ctl >/dev/null 2>&1; then
		printf '%s\n' "apache2ctl -D FOREGROUND"
	elif command -v apachectl >/dev/null 2>&1; then
		printf '%s\n' "apachectl -D FOREGROUND"
	else
		return 1
	fi
}

main() {
	resolve_env GLPI_DB_HOST "db" DB_HOST MYSQL_HOST MARIADB_HOST POSTGRES_HOST
	resolve_env GLPI_DB_PORT "3306" DB_PORT MYSQL_PORT MARIADB_PORT POSTGRES_PORT
	resolve_env GLPI_DB_NAME "" DB_NAME MYSQL_DATABASE MARIADB_DATABASE POSTGRES_DB
	resolve_env GLPI_DB_USER "" DB_USER MYSQL_USER MARIADB_USER POSTGRES_USER
	resolve_env GLPI_DB_PASSWORD "" DB_PASSWORD MYSQL_PASSWORD MARIADB_PASSWORD POSTGRES_PASSWORD
	resolve_env GLPI_ADMIN_USER "glpi" ADMIN_USER
	resolve_env GLPI_ADMIN_PASSWORD "" ADMIN_PASSWORD
	resolve_env GLPI_TIMEZONE "${TZ:-}" TIMEZONE
	resolve_env GLPI_LANGUAGE "" GLPI_LANG
	resolve_env GLPI_URL "" GLPI_BASE_URL GLPI_URI

	if [ -z "${GLPI_URL:-}" ] && [ -n "${GLPI_FQDN:-}" ]; then
		if [ "${GLPI_HTTPS:-false}" = "true" ]; then
			export GLPI_URL="https://${GLPI_FQDN}"
		else
			export GLPI_URL="http://${GLPI_FQDN}"
		fi
	fi

	: "${GLPI_DB_TYPE:=mysql}"
	export GLPI_DB_TYPE

	require_env GLPI_DB_HOST
	require_env GLPI_DB_PORT
	require_env GLPI_DB_NAME
	require_env GLPI_DB_USER
	require_env GLPI_DB_PASSWORD

	wait_for_database
	ensure_permissions
	configure_php_runtime
	run_setup
	start_cron

	if [ "$#" -gt 0 ]; then
		log "executing custom command: $*"
		exec "$@"
	fi

	local apache
	apache="$(apache_command)" || die "Apache foreground command not found"
	log "starting Apache in foreground on the image-configured port (expected 8080)"
	# shellcheck disable=SC2086
	exec $apache
}

main "$@"
