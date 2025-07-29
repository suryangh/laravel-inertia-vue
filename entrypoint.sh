#!/bin/sh

# Tunggu MySQL ready
until nc -z db 3306; do
  echo "Waiting for MySQL..."
  sleep 2
done

# Generate APP_KEY jika belum ada
if ! grep -q "^APP_KEY=base64:" .env; then
  php artisan key:generate --force
fi

# Jalankan migrate otomatis (bisa hapus --force jika ingin aman)
php artisan migrate --force || true

# Start supervisor (nginx + php-fpm)
exec /usr/bin/supervisord -c /etc/supervisord.conf
