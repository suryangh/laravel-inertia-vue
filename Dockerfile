# Multi-stage build dengan proper file structure
FROM node:18-alpine AS node-builder

WORKDIR /app

# Copy package files dan config files
COPY package*.json ./
COPY webpack.mix.js ./
COPY tailwind.config.js ./

# Copy ALL source files yang dibutuhkan untuk build
COPY resources/ ./resources/
COPY public/ ./public/


RUN npm install --ignore-scripts

COPY . .

# Build assets manually
RUN npm run production

# Main PHP image (SIMPLIFIED & OPTIMIZED)
FROM php:8.1-fpm-alpine

ENV TZ=Asia/Jakarta

# Install MINIMAL dependencies (hapus yang tidak perlu)
RUN apk add --no-cache \
    nginx \
    supervisor \
    mysql-client

# Install MINIMAL PHP extensions (hapus PostgreSQL, Redis, Intl)
RUN apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        libzip-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        freetype-dev \
        oniguruma-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        pdo_mysql \
        mbstring \
        zip \
        gd \
        opcache \
        bcmath \
    && apk del .build-deps \
    && rm -rf /var/cache/apk/*

# Install Composer
COPY --from=composer:2.5 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Copy aplikasi
COPY . .

# Copy built assets dengan proper paths
COPY --from=node-builder /app/public/js ./public/js/
COPY --from=node-builder /app/public/css ./public/css/
COPY --from=node-builder /app/public/mix-manifest.json ./public/

# Install PHP dependencies
RUN composer install --no-dev --optimize-autoloader \
    && composer clear-cache

# Setup Laravel environment
RUN cp .env.example .env \
    && php artisan key:generate --force

# Set permissions
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html/storage \
    && chmod -R 755 /var/www/html/bootstrap/cache

# Create inline configs (TIDAK PERLU external nginx.conf & supervisord.conf)
RUN echo 'events { worker_connections 1024; } \
http { \
    include mime.types; \
    default_type application/octet-stream; \
    server { \
        listen 80; \
        root /var/www/html/public; \
        index index.php index.html; \
        \
        location / { \
            try_files $uri $uri/ /index.php?$query_string; \
        } \
        \
        location ~ \.php$ { \
            fastcgi_pass 127.0.0.1:9000; \
            fastcgi_index index.php; \
            include fastcgi_params; \
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name; \
        } \
        \
        location ~ /\.ht { \
            deny all; \
        } \
    } \
}' > /etc/nginx/nginx.conf

RUN mkdir -p /etc/supervisor/conf.d/ \
    && echo '[supervisord]' > /etc/supervisor/conf.d/supervisord.conf \
    && echo 'nodaemon=true' >> /etc/supervisor/conf.d/supervisord.conf \
    && echo '' >> /etc/supervisor/conf.d/supervisord.conf \
    && echo '[program:php-fpm]' >> /etc/supervisor/conf.d/supervisord.conf \
    && echo 'command=php-fpm -F' >> /etc/supervisor/conf.d/supervisord.conf \
    && echo 'stdout_logfile=/dev/stdout' >> /etc/supervisor/conf.d/supervisord.conf \
    && echo 'stdout_logfile_maxbytes=0' >> /etc/supervisor/conf.d/supervisord.conf \
    && echo 'stderr_logfile=/dev/stderr' >> /etc/supervisor/conf.d/supervisord.conf \
    && echo 'stderr_logfile_maxbytes=0' >> /etc/supervisor/conf.d/supervisord.conf \
    && echo '' >> /etc/supervisor/conf.d/supervisord.conf \
    && echo '[program:nginx]' >> /etc/supervisor/conf.d/supervisord.conf \
    && echo 'command=nginx -g "daemon off;"' >> /etc/supervisor/conf.d/supervisord.conf \
    && echo 'stdout_logfile=/dev/stdout' >> /etc/supervisor/conf.d/supervisord.conf \
    && echo 'stdout_logfile_maxbytes=0' >> /etc/supervisor/conf.d/supervisord.conf \
    && echo 'stderr_logfile=/dev/stderr' >> /etc/supervisor/conf.d/supervisord.conf \
    && echo 'stderr_logfile_maxbytes=0' >> /etc/supervisor/conf.d/supervisord.conf

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
