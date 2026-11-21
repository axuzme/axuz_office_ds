#!/usr/bin/env bash
set -u
DIR=/var/www/onlyoffice/documentserver
export NODE_ENV=production-linux NODE_CONFIG_DIR=/etc/onlyoffice/documentserver NODE_DISABLE_COLORS=1
export LD_LIBRARY_PATH=$DIR/server/FileConverter/bin
mkdir -p /var/lib/onlyoffice/documentserver/App_Data/cache/files /var/www/onlyoffice/Data /tmp/ds
( cd $DIR/server/FileConverter && ./converter > /var/log/onlyoffice/converter.log 2>&1 ) &
cd $DIR/server/DocService && exec ./docservice > /var/log/onlyoffice/docservice.log 2>&1
