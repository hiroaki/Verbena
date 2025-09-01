#!/bin/sh

# Rails から接続するためのユーザを作成します。
# docker-compose.yml にて環境変数 MYSQL_USER を設定していることで、
# このスクリプトの前の段階でその値のユーザが作成されることになっています。
# ここではそのユーザの権限について設定します。
mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "GRANT ALL PRIVILEGES ON verbena_development.* TO '${MYSQL_USER}'@'%';"
mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "GRANT ALL PRIVILEGES ON verbena_test.* TO '${MYSQL_USER}'@'%';"
mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "FLUSH PRIVILEGES;"

