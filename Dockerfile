FROM php:8.3-apache

ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

RUN apt-get update && apt-get install -y --no-install-recommends \
    unzip curl \
    && rm -rf /var/lib/apt/lists/*

RUN install-php-extensions \
    pdo_mysql mysqli mbstring gd zip curl opcache \
    bcmath intl soap exif sodium xsl \
    imagick calendar redis

RUN a2enmod rewrite headers expires

RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf \
    && sed -i 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf

COPY docker/php/jtl.ini /usr/local/etc/php/conf.d/jtl.ini
COPY docker/php/opcache.ini /usr/local/etc/php/conf.d/opcache.ini

COPY shop/ /tmp/shop/

RUN set -eux; \
    ZIP_FILE=$(find /tmp/shop -maxdepth 1 -type f -iname '*.zip' | head -n1); \
    if [ -n "$ZIP_FILE" ]; then \
        echo "Extracting $ZIP_FILE"; \
        unzip -q "$ZIP_FILE" -d /tmp/extracted; \
        INNER=$(find /tmp/extracted -mindepth 1 -maxdepth 1 -type d | head -n1); \
        if [ -f /tmp/extracted/index.php ]; then \
            cp -a /tmp/extracted/. /var/www/html/; \
        elif [ -n "$INNER" ] && [ -f "$INNER/index.php" ]; then \
            cp -a "$INNER"/. /var/www/html/; \
        else \
            cp -a /tmp/extracted/. /var/www/html/; \
        fi; \
        rm -rf /tmp/extracted; \
    else \
        echo "No ZIP found, copying shop/ contents directly"; \
        cp -a /tmp/shop/. /var/www/html/ 2>/dev/null || true; \
    fi; \
    rm -rf /tmp/shop; \
    find /var/www/html -mindepth 1 -maxdepth 1 -name '.gitkeep' -delete; \
    chown -R www-data:www-data /var/www/html; \
    find /var/www/html -type d -exec chmod 755 {} \;; \
    find /var/www/html -type f -exec chmod 644 {} \;

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -fsS http://localhost/ || exit 1

EXPOSE 80
