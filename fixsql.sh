#!/bin/bash
mkdir -p /var/run/mysqld
chown mysql:mysql /var/run/mysqld
/etc/init.d/mysql stop
mysqld_safe --skip-grant-tables &
echo "ok"
