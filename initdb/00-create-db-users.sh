#!/bin/sh

# 安全な初期化（冪等化）: 既に権限が付与されている場合は再実行をスキップします。
# Rails から接続するためのユーザを作成する想定です。
# compose.yml にて環境変数 MYSQL_USER を設定していることで、
# イメージ側でユーザが作成されるケースがあります。ここでは権限を付与します。

set -eu

# 必須環境変数の検証
: "${MYSQL_ROOT_PASSWORD?Need MYSQL_ROOT_PASSWORD env var}"
: "${MYSQL_USER?Need MYSQL_USER env var}"

SKIP_FLUSH=1

# helper: check if user has any entry in mysql.db for given database
has_privs_for_db() {
	db="$1"
	count=$(mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sse "SELECT COUNT(*) FROM mysql.db WHERE User='${MYSQL_USER}' AND Db='${db}'" || echo 0)
	[ "${count}" -gt 0 ]
}

echo "initdb: ensuring privileges for user ${MYSQL_USER}"

if has_privs_for_db "verbena_development"; then
	echo "initdb: privileges for ${MYSQL_USER} on verbena_development already present — skipping"
else
	echo "initdb: granting privileges on verbena_development to ${MYSQL_USER}"
	mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON verbena_development.* TO '${MYSQL_USER}'@'%';"
	SKIP_FLUSH=0
fi

if has_privs_for_db "verbena_test"; then
	echo "initdb: privileges for ${MYSQL_USER} on verbena_test already present — skipping"
else
	echo "initdb: granting privileges on verbena_test to ${MYSQL_USER}"
	mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON verbena_test.* TO '${MYSQL_USER}'@'%';"
	SKIP_FLUSH=0
fi

if [ "${SKIP_FLUSH}" -eq 0 ]; then
	echo "initdb: flushing privileges"
	mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
else
	echo "initdb: no changes; skipping FLUSH PRIVILEGES"
fi

exit 0

