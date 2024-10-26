#!/bin/bash
# trojan-go www一键安装脚本


RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

CONFIG_FILE="/etc/trojan-go/config.json"
NGINX_CONF_PATH="/etc/nginx/conf.d/"

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

checkSystem() {
    uid=$(id -u)
    if [[ $uid -ne 0 ]]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    res=$(command -v yum)
    if [[ "$res" = "" ]]; then
        res=$(command -v apt)
        if [[ "$res" = "" ]]; then
            colorEcho $RED " 不受支持的Linux系统"
            exit 1
        fi
        PMT="apt"
        CMD_INSTALL="apt install -y "
        CMD_REMOVE="apt remove -y "
        CMD_UPGRADE="apt update; apt upgrade -y; apt autoremove -y"
        PHP_SERVICE="php8.3-fpm"
    else
        PMT="yum"
        CMD_INSTALL="yum install -y "
        CMD_REMOVE="yum remove -y "
        CMD_UPGRADE="yum update -y"
        PHP_SERVICE="php-fpm"
        result=`grep -oE "[0-9.]+" /etc/centos-release`
        MAIN=${result%%.*}
    fi
    res=$(command -v systemctl)
    if [[ "$res" = "" ]]; then
        colorEcho $RED " 系统版本过低，请升级到最新版本"
        exit 1
    fi
}

checkTrojan() {

    DOMAIN=`grep sni $CONFIG_FILE | cut -d\" -f4`
    NGINX_CONFIG_FILE="$NGINX_CONF_PATH${DOMAIN}.conf"

    PORT=`grep local_port $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    [[ "$1" = "install" ]] && colorEcho $BLUE " 伪装域名：$DOMAIN"
    [[ "$1" = "install" ]] && colorEcho $BLUE " trojan-go监听端口：$PORT"
}

statusText() {
    res=$(command -v nginx)
    if [[ "$res" = "" ]]; then
        echo -e -n ${RED}Nginx未安装${PLAIN}
    else
        res=`ps aux | grep nginx | grep -v grep`
        [[ "$res" = "" ]] && echo -e -n ${RED}Nginx未运行${PLAIN} || echo -e -n ${GREEN}Nginx正在运行${PLAIN}
    fi
    echo -n ", "
    res=$(command -v php)
    if [[ "$res" = "" ]]; then
        echo -e -n ${RED}PHP未安装${PLAIN}
    else
        res=`ps aux | grep php | grep -v grep`
        [[ "$res" = "" ]] && echo -e -n ${RED}PHP未运行${PLAIN} || echo -e -n ${GREEN}PHP正在运行${PLAIN}
    fi
}

installPHP() {
    [[ "$PMT" = "apt" ]] && $PMT update
    $CMD_INSTALL curl wget ca-certificates
    if [[ "$PMT" = "yum" ]]; then 
        $CMD_INSTALL epel-release
        if [[ $MAIN -eq 7 ]]; then
            rpm -iUh https://rpms.remirepo.net/enterprise/remi-release-7.rpm
            sed -i '0,/enabled=0/{s/enabled=0/enabled=1/}' /etc/yum.repos.d/remi-php74.repo
        else
            dnf install https://rpms.remirepo.net/enterprise/remi-release-8.rpm
            sed -i '0,/enabled=0/{s/enabled=0/enabled=1/}' /etc/yum.repos.d/remi.repo
            dnf module install -y php:remi-7.4
        fi
        $CMD_INSTALL php-cli php-fpm php-bcmath php-gd php-mbstring php-mysqlnd php-pdo php-opcache php-xml php-pecl-zip  php-pecl-imagick
    else
        $CMD_INSTALL lsb-release gnupg2
        wget -q https://ppa:ondrej/php/apt.gpg -O- | apt-key add -
        echo "deb https://ppa:ondrej/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php7.list
        $PMT update
        $CMD_INSTALL php7.4-cli php7.4-fpm php7.4-bcmath php7.4-gd php7.4-mysql php7.4-mbstring php7.4-opcache php7.4-xml php7.4-zip php7.4-json php7.4-imagick
        update-alternatives --set php /usr/bin/php7.4
    fi
    systemctl enable $PHP_SERVICE
}


installWordPress() {
    mkdir -p /var/www/$DOMAIN
    cd  /var/www/$DOMAIN
    wget https://github.com/user-attachments/files/17529055/www.zip
    unzip www.zip
    rm -rf www.zip
}

config() {

    # config wordpress
    cd /var/www/$DOMAIN
    #sed -i "1a \$_SERVER['HTTPS']='on';" index.php
    perl -i -pe'
  BEGIN {
    @chars = ("a" .. "z", "A" .. "Z", 0 .. 9);
    push @chars, split //, "!@#$%^&*()-_ []{}<>~\`+=,.;:/?|";
    sub salt { join "", map $chars[ rand @chars ], 1 .. 64 }
  }
  s/put your unique phrase here/salt()/ge
' wp-config.php

    if [[ "$PMT" = "yum" ]]; then
        user="apache"
        # config nginx
        [[ $MAIN -eq 7 ]] && upstream="127.0.0.1:9000" || upstream="php-fpm"
    else
        user="www-data"
        upstream="unix:/run/php/php7.4-fpm.sock"
    fi
    chown -R $user:$user /var/www/${DOMAIN}

    # config nginx
    cat > $NGINX_CONFIG_FILE<<-EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    return 301 https://\$server_name:${PORT}\$request_uri;
}
server {
    listen 8080;
    server_name ${DOMAIN};
    
    charset utf-8;
    
    set \$host_path "/var/www/${DOMAIN}";
    access_log  /var/log/nginx/${DOMAIN}.access.log  main buffer=32k flush=30s;
    error_log /var/log/nginx/${DOMAIN}.error.log;
    root   \$host_path;
    location / {
        index  index.php index.html;
        try_files \$uri \$uri/ /index.php?\$args;
    }
    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_index index.php;
        fastcgi_pass $upstream;
        include fastcgi_params;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
	    fastcgi_param  SERVER_PORT	${PORT};
	    fastcgi_param  HTTPS		"on";
    }
    location ~ \.(js|css|png|jpg|jpeg|gif|ico|swf|webp|pdf|txt|doc|docx|xls|xlsx|ppt|pptx|mov|fla|zip|rar)\$ {
        expires max;
        access_log off;
        try_files \$uri =404;
    }
}
EOF

    # config trojan-go
    sed -i -e "s/remote_addr\":\s*\".*\",/remote_addr\": \"127.0.0.1\",/" $CONFIG_FILE
    sed -i -e "s/remote_port\":\s*[0-9]*/remote_port\": 8080/" $CONFIG_FILE
    sed -i -e "s/fallback_addr\":\s*\".*\",/fallback_addr\": \"127.0.0.1\",/" $CONFIG_FILE
    sed -i -e "s/fallback_port\":\s*[0-9]*/fallback_port\": 8080/" $CONFIG_FILE

    # restart service
    systemctl restart $PHP_SERVICE mariadb nginx trojan-go
}

install() {
    checkTrojan "install"
    installPHP
    installWordPress
    colorEcho $BLUE " WordPress安装成功！"

    config
    # restart service
    systemctl restart $PHP_SERVICE mariadb nginx

    sleep 2
    statusText
    echo ""

    showInfo
}

uninstall() {
    echo ""
    colorEcho $RED " 该操作会删除所有www文件！"
    read -p " 确认卸载www？[y/n]" answer
    [[ "$answer" != "y" && "$answer" != "Y" ]] && exit 0

    checkTrojan
    systemctl stop mariadb
    systemctl disable mariadb
    if [[ "$PMT" = "yum" ]]; then
        $CMD_REMOVE MariaDB-server
    else
        apt-get purge -y mariadb-*
    fi
    rm -rf /var/lib/mysql

    systemctl stop $PHP_SERVICE
    systemctl disable $PHP_SERVICE

    rm -rf /var/www/${DOMAIN}

    colorEcho $GREEN " 卸载成功！"
}

showInfo() {
    checkTrojan

    if [[ -z ${DBNAME+x} ]]; then
 
    fi
    if [[ "$PORT" = "443" ]]; then
        url="https://$DOMAIN"
    else
        url="https://$DOMAIN:$PORT"
    fi
    colorEcho $BLUE " www配置信息："
    echo "==============================="
    echo -e "   ${BLUE}www安装路径：${PLAIN}${RED}/var/www/${DOMAIN}${PLAIN}"
    echo -e "   ${BLUE}www网址：${PLAIN}${RED}$url${PLAIN}"
    echo "==============================="
}

help() {
    echo ""
    colorEcho $BLUE "  Nginx操作："
    colorEcho $GREEN "    启动: systemctl start nginx"
    colorEcho $GREEN "    停止：systemctl stop nginx"
    colorEcho $GREEN "    重启：systemctl restart nginx"
    echo " -------------"
    colorEcho $BLUE "  PHP操作："
    colorEcho $GREEN "    启动: systemctl start $PHP_SERVICE"
    colorEcho $GREEN "    停止：systemctl stop $PHP_SERVICE"
    colorEcho $GREEN "    重启：systemctl restart $PHP_SERVICE"
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#                ${RED}www一键安装脚本${PLAIN}                  #"
    echo "#############################################################"
    echo 
    colorEcho $YELLOW " 该脚本仅适用于网站上的trojan-go一键脚本安装wwww用！"
    echo 
    echo -e "  ${GREEN}1.${PLAIN} 安装www" 
    echo -e "  ${GREEN}2.${PLAIN} 卸载www"
    echo -e "  ${GREEN}3.${PLAIN} 查看www配置"
    echo -e "  ${GREEN}4.${PLAIN} 查看操作帮助"
    echo " -------------"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo -n " 当前状态："
    statusText
    echo 

    echo ""
    read -p " 请选择操作[0-4]：" answer
    case $answer in
        0)
            exit 0
            ;;
        1)
            install
            ;;
        2)
            uninstall
            ;;
        3)
            showInfo
            ;;
        4)
            help
            ;;
        *)
            colorEcho $RED " 请选择正确的操作！"
            exit 1
            ;;
    esac
}

checkSystem

menu

