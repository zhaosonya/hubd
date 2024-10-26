1.trojan-go一键脚本可运行在CentOS 7/8、Ubuntu 16/18/20、Debian 8/9/10等主流系统上，并且支持自定义域名证书（需放置在/root目录下并命名为trojan-go.pem和trojan-go.key）
2.请先登录vps管理后台放行80和443端口，否则可能会导致获取证书失败。
3.if 未检测到您服务器环境的pdo_sqlite数据库扩展 sudo apt-get install php7.4-sqlite
