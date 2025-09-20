docker compose exec db mariadb -e \
"CREATE DATABASE IF NOT EXISTS ghostdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'ghostuser'@'%' IDENTIFIED BY 'mystrongpassword';
ALTER USER 'ghostuser'@'%' IDENTIFIED BY 'mystrongpassword';
GRANT ALL PRIVILEGES ON ghostdb.* TO 'ghostuser'@'%';
FLUSH PRIVILEGES;"