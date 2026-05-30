#!/usr/bin/env bash
set -Eeuo pipefail

log() {
	printf '%s\n' "glpi-setup: $*"
}

warn() {
	printf '%s\n' "glpi-setup: warning: $*" >&2
}

die() {
	printf '%s\n' "glpi-setup: error: $*" >&2
	exit 1
}

write_php_define_file() {
	local file="$1"
	local tmp="${file}.tmp"
	shift

	mkdir -p "$(dirname "$file")"
	{
		printf '%s\n' "<?php"
		while [ "$#" -gt 0 ]; do
			printf "%s\n" "$1"
			shift
		done
	} >"$tmp"
	mv "$tmp" "$file"
}

run_glpi() {
	local console="$1"
	shift

	if [ "$(id -u)" = "0" ] && command -v runuser >/dev/null 2>&1 && id glpi >/dev/null 2>&1; then
		runuser -u glpi -- php "$console" "$@"
	else
		php "$console" "$@"
	fi
}

run_glpi_optional() {
	local console="$1"
	shift

	if ! run_glpi "$console" "$@"; then
		warn "optional GLPI command failed: $*"
		return 1
	fi
}

mysql_table_exists() {
	local table="$1"

	# shellcheck disable=SC2153
	MYSQL_PWD="${GLPI_DB_PASSWORD}" mysql \
		--host="${GLPI_DB_HOST}" \
		--port="${GLPI_DB_PORT}" \
		--user="${GLPI_DB_USER}" \
		--database="${GLPI_DB_NAME}" \
		--batch \
		--skip-column-names \
		--execute="show tables like '${table}'" 2>/dev/null | grep -qx "${table}"
}

postgres_table_exists() {
	local table="$1"

	PGPASSWORD="${GLPI_DB_PASSWORD}" psql \
		-h "${GLPI_DB_HOST}" \
		-p "${GLPI_DB_PORT}" \
		-U "${GLPI_DB_USER}" \
		-d "${GLPI_DB_NAME}" \
		-tAc "select to_regclass('public.${table}')" 2>/dev/null | grep -qx "${table}"
}

database_has_glpi() {
	case "${GLPI_DB_TYPE}" in
		mysql|mysqli|mariadb)
			if command -v mysql >/dev/null 2>&1; then
				mysql_table_exists "glpi_configs" || mysql_table_exists "glpi_migrations"
				return
			fi
			;;
		pgsql|postgres|postgresql)
			if command -v psql >/dev/null 2>&1; then
				postgres_table_exists "glpi_configs" || postgres_table_exists "glpi_migrations"
				return
			fi
			;;
	esac

	[ -f "${GLPI_CONFIG_DIR}/config_db.php" ] || [ -f "${GLPI_CONFIG_DIR}/local_define.php" ]
}

console_has_command() {
	local console="$1"
	local command_name="$2"

	php "$console" list --raw 2>/dev/null | awk '{ print $1 }' | grep -qx "$command_name"
}

console_command_has_option() {
	local console="$1"
	local command_name="$2"
	local option_name="$3"

	php "$console" help "$command_name" 2>/dev/null | grep -q -- "$option_name"
}

php_literal() {
	PHP_LITERAL_VALUE="$1" php -r 'echo var_export(getenv("PHP_LITERAL_VALUE"), true);'
}

php_config_set() {
	local file="$1"
	local key="$2"
	local value="$3"

	PHP_CONFIG_FILE="$file" \
		PHP_CONFIG_KEY="$key" \
		PHP_CONFIG_VALUE="$value" \
		php -r "$(cat <<'PHPEOF'
$file = getenv("PHP_CONFIG_FILE");
$key = getenv("PHP_CONFIG_KEY");
$value = getenv("PHP_CONFIG_VALUE");
$cfg = is_file($file) ? include $file : array();
if (!is_array($cfg)) { $cfg = array(); }
$cfg[$key] = $value;
file_put_contents($file, "<?php" . PHP_EOL . "return " . var_export($cfg, true) . ";" . PHP_EOL);
PHPEOF
)"
}

configure_local_defaults() {
	local local_config="$1"

	mkdir -p "$(dirname "$local_config")"

	if [ -n "${GLPI_TIMEZONE:-}" ]; then
		php_config_set "$local_config" "timezone" "$GLPI_TIMEZONE"
		log "configured timezone default (${GLPI_TIMEZONE})"
	fi

	if [ -n "${GLPI_LANGUAGE:-}" ]; then
		php_config_set "$local_config" "language" "$GLPI_LANGUAGE"
		log "configured language default (${GLPI_LANGUAGE})"
	fi

	if [ -n "${GLPI_URL:-}" ]; then
		php_config_set "$local_config" "url_base" "$GLPI_URL"
		log "configured URL base (${GLPI_URL})"
	fi
}

configure_console_defaults() {
	local console="$1"

	if [ -z "${GLPI_TIMEZONE:-}" ] && [ -z "${GLPI_LANGUAGE:-}" ] && [ -z "${GLPI_URL:-}" ]; then
		return 0
	fi

	if ! console_has_command "$console" "config:set"; then
		warn "GLPI CLI config:set command is unavailable; kept filesystem defaults only"
		return 0
	fi

	if [ -n "${GLPI_TIMEZONE:-}" ]; then
		run_glpi_optional "$console" config:set timezone "$GLPI_TIMEZONE" --no-interaction
	fi

	if [ -n "${GLPI_LANGUAGE:-}" ]; then
		run_glpi_optional "$console" config:set language "$GLPI_LANGUAGE" --no-interaction
	fi

	if [ -n "${GLPI_URL:-}" ]; then
		run_glpi_optional "$console" config:set url_base "$GLPI_URL" --no-interaction
	fi
}

configure_external_paths() {
	local downstream="${GLPI_ROOT}/inc/downstream.php"
	local local_define="${GLPI_CONFIG_DIR}/local_define.php"
	local config_dir
	local var_dir
	local log_dir
	local marketplace_dir

	config_dir="$(php_literal "$GLPI_CONFIG_DIR")"
	var_dir="$(php_literal "$GLPI_VAR_DIR")"
	log_dir="$(php_literal "$GLPI_LOG_DIR")"
	marketplace_dir="$(php_literal "$GLPI_MARKETPLACE_DIR")"

	if [ ! -f "$downstream" ]; then
		if [ -w "$(dirname "$downstream")" ]; then
			write_php_define_file "$downstream" \
				"defined('GLPI_CONFIG_DIR') || define('GLPI_CONFIG_DIR', ${config_dir});"
			log "created downstream path definition (${downstream})"
		else
			warn "cannot create ${downstream}; pre-create it in the image or run setup once as root so GLPI can use ${GLPI_CONFIG_DIR}"
		fi
	fi

	write_php_define_file "$local_define" \
		"defined('GLPI_VAR_DIR') || define('GLPI_VAR_DIR', ${var_dir});" \
		"defined('GLPI_LOG_DIR') || define('GLPI_LOG_DIR', ${log_dir});" \
		"defined('GLPI_MARKETPLACE_DIR') || define('GLPI_MARKETPLACE_DIR', ${marketplace_dir});"
	log "configured GLPI runtime directories"
}

configure_admin() {
	local console="$1"

	if [ -z "${GLPI_ADMIN_USER:-}" ] && [ -z "${GLPI_ADMIN_PASSWORD:-}" ]; then
		return 0
	fi

	[ -n "${GLPI_ADMIN_USER:-}" ] || die "GLPI_ADMIN_USER is required when GLPI_ADMIN_PASSWORD is set"
	[ -n "${GLPI_ADMIN_PASSWORD:-}" ] || die "GLPI_ADMIN_PASSWORD is required when GLPI_ADMIN_USER is set"

	if console_has_command "$console" "user:create"; then
		if run_glpi "$console" user:create \
			--login="${GLPI_ADMIN_USER}" \
			--password="${GLPI_ADMIN_PASSWORD}" \
			--profile="Super-Admin" \
			--no-interaction; then
			log "created initial admin user ${GLPI_ADMIN_USER}"
			return 0
		fi
		warn "admin user creation did not complete; it may already exist"
	fi

	if console_has_command "$console" "user:update"; then
		if run_glpi "$console" user:update \
			--login="${GLPI_ADMIN_USER}" \
			--password="${GLPI_ADMIN_PASSWORD}" \
			--no-interaction; then
			log "updated admin user ${GLPI_ADMIN_USER}"
			return 0
		fi
		warn "admin user update did not complete"
	fi

	warn "this GLPI CLI does not expose a supported admin create/update command; leaving admin credentials unchanged"
}

main() {
	: "${GLPI_ROOT:=/var/www/html}"
	: "${GLPI_DB_HOST:?GLPI_DB_HOST is required}"
	: "${GLPI_DB_PORT:=5432}"
	: "${GLPI_DB_NAME:?GLPI_DB_NAME is required}"
	: "${GLPI_DB_USER:?GLPI_DB_USER is required}"
	: "${GLPI_DB_PASSWORD:?GLPI_DB_PASSWORD is required}"
	: "${GLPI_DB_TYPE:=mysql}"

	case "${GLPI_DB_TYPE}" in
		mysql|mysqli|mariadb)
			;;
		pgsql|postgres|postgresql)
			die "GLPI 10.0.18 does not support PostgreSQL as application database; use GLPI_DB_TYPE=mysql with MariaDB/MySQL"
			;;
		*)
			die "unsupported GLPI_DB_TYPE=${GLPI_DB_TYPE}; use mysql/mariadb"
			;;
	esac
	[ -d "$GLPI_ROOT" ] || die "GLPI_ROOT does not exist: ${GLPI_ROOT}"

	local console="${GLPI_ROOT}/bin/console"
	local local_config

	: "${GLPI_CONFIG_DIR:=/var/lib/glpi/config}"
	: "${GLPI_VAR_DIR:=/var/lib/glpi/files}"
	: "${GLPI_MARKETPLACE_DIR:=/var/lib/glpi/marketplace}"
	: "${GLPI_PLUGINS_DIR:=/var/lib/glpi/plugins}"
	: "${GLPI_LOG_DIR:=${GLPI_VAR_DIR}/_log}"
	local_config="${GLPI_CONFIG_DIR}/local_config.php"

	[ -f "$console" ] || die "GLPI console was not found at ${console}"

	configure_external_paths
	configure_local_defaults "$local_config"

	if database_has_glpi; then
		local update_args=(
			db:update
			--no-interaction
		)

		if console_command_has_option "$console" "db:update" "--force"; then
			update_args+=(--force)
		fi

		log "existing GLPI installation detected; running migrations"
		run_glpi "$console" "${update_args[@]}"
	else
		local install_args=(
			db:install
			--db-host="${GLPI_DB_HOST}"
			--db-port="${GLPI_DB_PORT}"
			--db-name="${GLPI_DB_NAME}"
			--db-user="${GLPI_DB_USER}"
			--db-password="${GLPI_DB_PASSWORD}"
			--no-interaction
		)

		if console_command_has_option "$console" "db:install" "--force"; then
			install_args+=(--force)
		fi

		if [ -n "${GLPI_LANGUAGE:-}" ] && console_command_has_option "$console" "db:install" "--default-language"; then
			install_args+=(--default-language="${GLPI_LANGUAGE}")
		fi

		log "no GLPI installation detected; running CLI installer"
		run_glpi "$console" "${install_args[@]}"
	fi

	configure_console_defaults "$console"
	configure_admin "$console"
}

main "$@"
