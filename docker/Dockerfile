FROM php:8.3-apache-bookworm

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG GLPI_VERSION=10.0.18
ARG GLPI_SHA256=fe044e021c17ee88e088a8a4392c7807c9a0f397a1a551689d2eb7f668439e96

ENV GLPI_VERSION="${GLPI_VERSION}" \
    GLPI_SHA256="${GLPI_SHA256}" \
    GLPI_ROOT="/var/www/html" \
    GLPI_CONFIG_DIR="/var/lib/glpi/config" \
    GLPI_VAR_DIR="/var/lib/glpi/files" \
    GLPI_MARKETPLACE_DIR="/var/lib/glpi/marketplace" \
    GLPI_PLUGINS_DIR="/var/lib/glpi/plugins" \
    GLPI_LOG_DIR="/var/lib/glpi/files/_log" \
    PHP_INI_SCAN_DIR="/usr/local/etc/php/conf.d:/var/lib/glpi/php-conf.d" \
    APACHE_RUN_USER="glpi" \
    APACHE_RUN_GROUP="glpi" \
    APACHE_PID_FILE="/var/run/apache2/apache2.pid" \
    APACHE_RUN_DIR="/var/run/apache2" \
    APACHE_LOCK_DIR="/var/lock/apache2" \
    APACHE_LOG_DIR="/var/log/apache2"

# hadolint ignore=DL3008,SC2086
RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bzip2 \
        ca-certificates \
        cron \
        curl \
        default-mysql-client \
        libbz2-dev \
        libcurl4-openssl-dev \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libldap2-dev \
        libonig-dev \
        libpng-dev \
        libpq-dev \
        libwebp-dev \
        libxml2-dev \
        libzip-dev \
        postgresql-client \
        unzip; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-configure ldap; \
    docker-php-ext-install -j"$(nproc)" \
        bz2 \
        exif \
        gd \
        intl \
        ldap \
        mysqli \
        opcache \
        pdo_pgsql \
        pgsql \
        zip; \
    php -m | grep -Eiq '^pdo$'; \
    php -m | grep -Eiq '^curl$'; \
    php -m | grep -Eiq '^mbstring$'; \
    php -m | grep -Eiq '^xml$'; \
    php -m | grep -Eiq '^sodium$'; \
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual \
        $savedAptMark \
        ca-certificates \
        cron \
        curl \
        default-mysql-client \
        libbz2-1.0 \
        libfreetype6 \
        libicu72 \
        libjpeg62-turbo \
        libldap-2.5-0 \
        libpng16-16 \
        libpq5 \
        libsasl2-2 \
        libwebp7 \
        libzip4 \
        postgresql-client > /dev/null; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    groupadd --gid 10001 glpi; \
    useradd --uid 10001 --gid 10001 --home-dir /var/lib/glpi --shell /usr/sbin/nologin glpi

RUN set -eux; \
    curl -LfsS "https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz" -o /tmp/glpi.tgz; \
    echo "${GLPI_SHA256}  /tmp/glpi.tgz" | sha256sum -c -; \
    rm -rf /var/www/html; \
    mkdir -p /var/www/html; \
    tar -xzf /tmp/glpi.tgz -C /var/www/html --strip-components=1; \
    rm /tmp/glpi.tgz; \
    rm -f /var/www/html/install/install.php; \
    mkdir -p \
        /var/lib/glpi/config \
        /var/lib/glpi/files/_cache \
        /var/lib/glpi/files/_cron \
        /var/lib/glpi/files/_dumps \
        /var/lib/glpi/files/_graphs \
        /var/lib/glpi/files/_lock \
        /var/lib/glpi/files/_log \
        /var/lib/glpi/files/_pictures \
        /var/lib/glpi/files/_plugins \
        /var/lib/glpi/files/_rss \
        /var/lib/glpi/files/_sessions \
        /var/lib/glpi/files/_tmp \
        /var/lib/glpi/files/_uploads \
        /var/lib/glpi/marketplace \
        /var/lib/glpi/php-conf.d \
        /var/lib/glpi/plugins; \
    printf '%s\n' '<?php' "defined('GLPI_CONFIG_DIR') || define('GLPI_CONFIG_DIR', '/var/lib/glpi/config');" > /var/www/html/inc/downstream.php; \
    rm -rf /var/www/html/marketplace /var/www/html/plugins; \
    ln -s /var/lib/glpi/marketplace /var/www/html/marketplace; \
    ln -s /var/lib/glpi/plugins /var/www/html/plugins; \
    chown -R root:root /var/www/html; \
    chown -R glpi:glpi /var/lib/glpi

COPY docker/config/apache-glpi.conf /etc/apache2/sites-available/000-default.conf
COPY docker/config/glpi-php.ini /usr/local/etc/php/conf.d/zz-glpi-production.ini
COPY docker/config/glpi-cron /etc/cron.d/glpi
COPY docker/config/glpi-public.htaccess /var/www/html/public/.htaccess
COPY --chmod=0755 docker/bin/ /usr/local/bin/

RUN set -eux; \
    a2enmod headers rewrite remoteip; \
    chmod 0644 /etc/cron.d/glpi; \
    mkdir -p /var/run/apache2 /var/lock/apache2 /var/log/apache2; \
    chown -R glpi:glpi /var/run/apache2 /var/lock/apache2 /var/log/apache2; \
    sed -ri \
        -e 's/^Listen 80$/# Listen 80 disabled; GLPI listens on 8080/' \
        /etc/apache2/ports.conf; \
    apache2ctl -t; \
    php -m | grep -Eiq '^mysqli$'; \
    php -m | grep -Eiq '^pgsql$'; \
    php -m | grep -Eiq '^pdo$'; \
    php -m | grep -Eiq '^pdo_pgsql$'; \
    php -m | grep -Eiq '^intl$'; \
    php -m | grep -Eiq '^gd$'; \
    php -m | grep -Eiq '^zip$'; \
    php -m | grep -Eiq '^bz2$'; \
    php -m | grep -Eiq '^ldap$'; \
    php -m | grep -Eiq 'opcache'; \
    php -m | grep -Eiq '^xml$'; \
    php -m | grep -Eiq '^curl$'; \
    php -m | grep -Eiq '^mbstring$'; \
    php -m | grep -Eiq '^exif$'; \
    php -m | grep -Eiq '^sodium$'

USER glpi

EXPOSE 8080

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
