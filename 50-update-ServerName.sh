source ${HTTPD_CONTAINER_SCRIPTS_PATH}/common.sh

sed -i -e 's/#ServerName www.example.com:443/ServerName ${SERVER_NAME}/' ${HTTPD_MAIN_CONF_D_PATH}/ssl.conf
