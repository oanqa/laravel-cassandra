ARG PHP_VERSION=8
ARG NGINX_VERSION=1.19

# "php" stage
FROM php:${PHP_VERSION}-fpm-alpine AS php

RUN apk add --no-cache \
		acl \
		curl \
		fcgi \
		file \
		gettext \
		git \
		gnupg \
		jq \
	;

RUN set -eux; \
	apk add --no-cache --virtual .cassandra-deps \
		$PHPIZE_DEPS \
		cassandra-cpp-driver-dev \
		libuv-dev \
		gmp-dev \
	; \
	mkdir /tmp/cassandra; \
	mkdir /tmp/cassandra/build; \
	curl -L -o /tmp/cassandra.tar.gz "https://github.com/oanqa/php-driver/archive/master.tar.gz"; \
	tar xfz /tmp/cassandra.tar.gz --strip 1 -C /tmp/cassandra; \
	cd /tmp/cassandra/ext && phpize; \
	cd /tmp/cassandra/build; \
	../ext/configure > /dev/null; \
	make clean > /dev/null; \
	make > /dev/null 2>&1; \
	make install; \
	docker-php-ext-enable cassandra; \
	rm /tmp/cassandra.tar.gz; \
	rm -rf /tmp/cassandra; \
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --no-cache --virtual .phpexts-rundeps $runDeps; \
	apk del .cassandra-deps

COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin

RUN set -eux; \
	install-php-extensions \
		apcu \
		exif \
		gd \
		gmp \
		intl \
		pdo_pgsql \
		redis \
		zip \
	;

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

RUN ln -s $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini
COPY docker/php/conf.d/app.prod.ini $PHP_INI_DIR/conf.d/app.ini

RUN set -eux; \
	{ \
		echo '[www]'; \
		echo 'ping.path = /ping'; \
	} | tee /usr/local/etc/php-fpm.d/docker-healthcheck.conf

ENV COMPOSER_ALLOW_SUPERUSER=1
ENV PATH="${PATH}:/root/.composer/vendor/bin"
WORKDIR /srv/app

ARG APP_ENV=prod
COPY composer.json composer.lock ./
RUN set -eux; \
	composer install --prefer-dist --no-dev --no-scripts --no-progress; \
	composer clear-cache

COPY app app/
COPY bootstrap bootstrap/
COPY config config/
COPY database database/
COPY resources resources/
COPY public public/
COPY routes routes/
COPY storage storage/
COPY artisan artisan
COPY .env .env

RUN set -eux; \
	composer dump-autoload --classmap-authoritative --no-dev; \
	chmod +x artisan; sync

COPY docker/php/docker-healthcheck.sh /usr/local/bin/docker-healthcheck
RUN chmod +x /usr/local/bin/docker-healthcheck

HEALTHCHECK --interval=10s --timeout=3s --retries=3 CMD ["docker-healthcheck"]

COPY docker/php/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/docker-entrypoint

ENTRYPOINT ["docker-entrypoint"]
CMD ["php-fpm"]

# "nginx" stage
FROM nginx:${NGINX_VERSION}-alpine AS nginx
COPY docker/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf
WORKDIR /srv/app/public
COPY public ./
