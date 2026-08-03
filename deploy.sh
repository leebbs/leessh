#!/bin/bash
# Define Color
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No color

current_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

CONNECTION_TIME=3                                                                   # curl超时时间
CONNECTION_MAX_TIME=5                                                               # curl最大超时时间
ServerPort=80
PublicIP="111"
SignalType=""                                                                       # 信号定义
DEPLOY_ROOT_DIR="/app"
DEPLOY_PROJECT_DIR="$DEPLOY_ROOT_DIR/gs"
DEPLOY_PROJECT_BIN="$DEPLOY_PROJECT_DIR/bin"
DEPLOY_PROJECT_CONFIG="$DEPLOY_ROOT_DIR/config"
DEPLOY_PROJECT_MAIN="$DEPLOY_PROJECT_DIR/bin/gs_main"
DEPLOY_PROJECT_MAIN_FILE="./gs_main"
GM_ServiceUser="root"                                                               # 运行服务的用户
GM_ServiceGroup="root"
SERVICE_NAME="GMServer"
GM_SERVICE_DIR="/etc/systemd/system"      
GM_SERVICE_FILE="$GM_SERVICE_DIR/$SERVICE_NAME.service"                             # 服务配置文件路径
GM_SERVICE_BUILD_CONFIG_FILE="$DEPLOY_PROJECT_DIR/config/config.json"
GM_SERVICE_CONFIG_FILE="$DEPLOY_PROJECT_CONFIG/config.json"
GM_ServiceLogDir="/app/gs/logs"  
GM_ServiceErrorLog="$GM_ServiceLogDir/error.log"                                             # 错误日志
GM_ServiceOutputLog="$GM_ServiceLogDir/output.log"   

Init_Env() {
    echo "[*] Check whether user permissions can be installed normally"
    # TODO: 先暂时不考虑Root用户离线部署
    if [ $(whoami) != "root" ];then
        echo "[-] Installation by non-root users is not currently supported"
    else
        echo "[+] User permissions are normal"
    fi

    if [ ! -f "$DEPLOY_PROJECT_MAIN" ]; then
        rm -rf $DEPLOY_PROJECT_DIR
        declare -a dirs_to_create=(
            "$DEPLOY_PROJECT_DIR"
            "$GM_SERVICE_DIR"
            "$GM_ServiceLogDir"
            "$DEPLOY_PROJECT_CONFIG"
        )
        for dir in "${dirs_to_create[@]}"; do
            if [ ! -d "$dir" ]; then
                sudo mkdir -p "$dir"
                sudo chmod 755 "$dir"
            fi
        done
        cp -r $current_dir/* $DEPLOY_PROJECT_DIR
        mv -f $GM_SERVICE_BUILD_CONFIG_FILE $DEPLOY_PROJECT_CONFIG
        rm -rf $DEPLOY_PROJECT_BIN/config
        echo -e "${GREEN}[+] Directory initialization completed${NC}"
    else
        echo -e "${GREEN}[+] Directory initialization completed${NC}"
    fi
    echo -e "${GREEN}[+] You can use the start command to start the service...V(^_^)V${NC}"
}

Run_Project() {
    if [ ! -f "$DEPLOY_PROJECT_MAIN" ]; then
        echo -e "${RED}Error: file '$file' does not exist${NC}"
        echo -e "${RED}Service startup failed...${NC}"
        echo -e "${RED}Please use the init command to initialize the service and then try to start the service...${NC}"
        exit 1
    fi
    cd $DEPLOY_PROJECT_BIN
    $DEPLOY_PROJECT_MAIN_FILE http
}

check_main() {
    if [ ! -f "$DEPLOY_PROJECT_MAIN" ]; then
        echo -e "${RED}Error: file '$file' does not exist${NC}"
        echo -e "${RED}Service startup failed...${NC}"
        echo -e "${RED}Please use the init command to initialize the service and then try to start the service...${NC}"
        exit 1
    fi
}

check_main_service() {
    if [ ! -f "$GM_SERVICE_FILE" ]; then
        echo -e "${RED}Error: file '$file' does not exist${NC}"
        echo -e "${RED}Service startup failed...${NC}"
        echo -e "${RED}Please use the init command to initialize the service and then try to start the service...${NC}"
        exit 1
    fi
}

Run_Project_Damon() {
    if [ ! -f "$DEPLOY_PROJECT_MAIN" ]; then
        echo -e "${RED}Error: file '$file' does not exist${NC}"
        echo -e "${RED}Service startup failed...${NC}"
        echo -e "${RED}Please use the init command to initialize the service and then try to start the service...${NC}"
        exit 1
    fi
    cd $DEPLOY_PROJECT_BIN
    nohup $DEPLOY_PROJECT_MAIN_FILE http &
}


Install_ENV_Check(){
    CURL_CHECK=$(which curl)
    if [ "$?" == "0" ];then
        echo "[+] Check curl $?"
    else
        echo "[-] Check whether the curl command is installed in the environment"
        exit 1
    fi
    echo "[*] Environment check: curl is installed  $CURL_CHECK"

    if ! command -v systemctl &> /dev/null; then
        echo "[-] Error: The current system does not support systemd, cannot continue"
        exit 1
    fi
}


create_service_file() {                                                             # 创建systemd服务配置文件
    echo "[-] Creating a Service Profile $GM_SERVICE_FILE..."                       # /etc/systemd/system/myscript.service
    if [ -f "$GM_SERVICE_FILE" ]; then
        rm -rf "$GM_SERVICE_FILE"
    fi
    cat > "$GM_SERVICE_FILE" << EOF                                                 # TODO: 使用systemctl管理服务
[Unit]
Description=$SERVICE_NAME Service
After=network.target

[Service]
ExecStart=$DEPLOY_PROJECT_MAIN http
User=$GM_ServiceUser
Group=$GM_ServiceGroup
WorkingDirectory=$DEPLOY_PROJECT_BIN
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Restart=always
RestartSec=5
StandardOutput=append:$GM_ServiceOutputLog
StandardError=append:$GM_ServiceErrorLog
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF
    if [ ! -f "$GM_SERVICE_FILE" ]; then                                            # 检查配置文件是否创建成功
        echo "[-] Error: Service profile creation failed"
        exit 1
    fi
    Check_Server_Port
    touch $GM_ServiceErrorLog
    touch $GM_ServiceOutputLog
    systemctl daemon-reload
}

Start_Deploy() {
    Install_ENV_Check
    Init_Env
    create_service_file
    show_gm_help
}

Get_ServerPort() {
    if [ -e "$GM_SERVICE_CONFIG_FILE" ]; then
        ServerPort=$(grep "http_port" $GM_SERVICE_CONFIG_FILE | grep -o -P '\d+')
        echo "[+] Port : $ServerPort"
    else
        echo "[-] Configuration file not found, please reinstall..."
        exit 1
    fi
}

Get_Public_IP(){
    echo "Read the server's external IP address"
    PublicIP=$(curl --connect-timeout "$CONNECTION_TIME" --max-time "$CONNECTION_MAX_TIME" -s icanhazip.com)
    Get_ServerPort
}
Get_Local_Ip(){
    echo "Obtain the IP address of the local network"
    LocalIP=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')
    Get_ServerPort
}

Check_Server_Port() {
    Get_ServerPort
    PORT=$ServerPort
    echo "Port number for current service configuration: $PORT"
    echo "Checking if port $PORT is occupied ..."
    echo "----------------------------------------"

    # 检测端口占用（优先使用lsof，兼容Linux和macOS）
    # 若lsof不存在，使用netstat检测（Linux系统）
    if command -v netstat &> /dev/null; then
        RESULT=$(netstat -tuln | grep -F ":$PORT " 2>/dev/null)
        if [ -n "$RESULT" ]; then
            echo "Port $PORT is already occupied, network connection information:"
            echo "$RESULT"
            echo "Tip: Use 'Sudo Netstat - tulnp | grep: $PORT' to view process IDs"
            echo -e "${RED}建议：可以修改端口号后启动服务 \ 
            Suggestion: You can start the service after modifying the port number${NC}"
            echo -e "${RED}建议：使用bash deploy.sh setport命令设置端口号 \ 
            Suggestion: Use the bash deploy.sh setport command to set the port number...${NC}"
            exit 0
        else
            echo "Port $PORT is not occupied"
        fi
    else
        # 若netstat也不存在，使用ss检测（较新的Linux系统）
        if command -v ss &> /dev/null; then
            RESULT=$(ss -tuln | grep ":$PORT" 2>/dev/null)
            if [ -n "$RESULT" ]; then
                echo "Port $PORT is already occupied, network connection information:"
                echo "$RESULT"
                echo "Tip: Use 'sudo ss tulnp | grep: $PORT' to view process IDs"
                echo -e "${RED}建议：可以修改端口号后启动服务 \ 
                Suggestion: You can start the service after modifying the port number${NC}"
                echo -e "${RED}建议：使用bash deploy.sh setport命令设置端口号 \ 
                Suggestion: Use the bash deploy.sh setport command to set the port number...${NC}"
                exit 0
            else
                echo "Port $PORT is not occupied"
            fi
        else
            # 若netstat也不存在，使用ss检测（较新的Linux系统）
            if command -v lsof &> /dev/null; then
                # 使用lsof检测，显示占用进程详情
                RESULT=$(lsof -i :$PORT 2>/dev/null)
                if [ -n "$RESULT" ]; then
                    echo "Port $PORT is already occupied, process information is as follows:"
                    echo "$RESULT" | awk 'NR==1 || $1!="COMMAND"'  # 过滤重复的COMMAND行
                    echo -e "${RED}建议：可以修改端口号后启动服务 \ 
                    Suggestion: You can start the service after modifying the port number${NC}"
                    echo -e "${RED}建议：使用bash deploy.sh setport命令设置端口号 \ 
                    Suggestion: Use the bash deploy.sh setport command to set the port number...${NC}"
                    exit 0
                else
                    echo "Port $PORT is not occupied"
                fi
            else
                echo "Error: Detection tool (lsof/netstat/ss) not found, unable to detect port"
                exit 0
            fi
        fi
    fi

    echo "----------------------------------------"
}

start_gm_service() {
    check_main
    check_main_service
    Check_Server_Port
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "[*] Start $SERVICE_NAME service..."
        systemctl start "$SERVICE_NAME" || {
            echo "[-] Error: Service start failed"
            exit 1
        }
        echo "[+] Service started successfully"
    else
        echo "[+] $SERVICE_NAME Service already running"
    fi

    Get_Public_IP
    Get_Local_Ip
    Start_Done
}

restart_gm_service() {
    check_main
    check_main_service
    Check_Server_Port
    echo "[*] Restart $SERVICE_NAME service..."
    systemctl restart "$SERVICE_NAME" || {
        echo "[-] Error: Service restart failed"
        exit 1
    }
    echo "[+] Service restarted successfully"
    Get_Public_IP
    Get_Local_Ip
    Start_Done
}

status_gm_service() {
    check_main
    check_main_service
    echo "[*] View $SERVICE_NAME Service Status..."
    systemctl status "$SERVICE_NAME"
}

enable_gm_service() {
    check_main
    check_main_service
    echo "[*] Enable $SERVICE_NAME automatic startup..."
    systemctl enable "$SERVICE_NAME" || {
        echo "[-] Error: Failed to set auto-start"
        exit 1
    }
    echo "[+] The automatic startup setting is successful"
}

disable_gm_service() {
    check_main
    check_main_service
    echo "[*] Disable $SERVICE_NAME automatic startup..."
    systemctl disable "$SERVICE_NAME" || {
        echo "[-] Error: Failed to cancel the automatic start"
        exit 1
    }
    echo "[*] Automatic startup has been canceled"
}

# 停止服务
stop_gm_service() {
    check_main
    check_main_service
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "[*] Stop $SERVICE_NAME server..."
        systemctl stop "$SERVICE_NAME" || {
            echo "[-] Error: Service stop failed"
            exit 1
        }
        echo "[+] Service stopped successfully"
    else
        echo "[+] $SERVICE_NAME The service is not running"
    fi
}

check_port_occupied() {
    PORT="$1"
    if command -v netstat &> /dev/null; then
        RESULT=$(netstat -tuln | grep -F ":$PORT " 2>/dev/null)
        if [ -n "$RESULT" ]; then
            echo "Port is already occupied"
            echo "Suggestion: Use the bash deploy.sh setport command to set the port number..."
            exit 0
        fi
    elif command -v ss &> /dev/null; then
        RESULT=$(ss -tuln | grep ":$PORT" 2>/dev/null)
        if [ -n "$RESULT" ]; then
            echo "Port is already occupied"
            echo "Suggestion: Use the bash deploy.sh setport command to set the port number..."
            exit 0
    fi
    elif command -v lsof &> /dev/null; then
        RESULT=$(lsof -i :$PORT 2>/dev/null)
        if [ -n "$RESULT" ]; then
            echo "Port is already occupied"
            echo "Suggestion: Use the bash deploy.sh setport command to set the port number..."
            exit 0
        fi
    else
        echo "Port is not occupied"
    fi
}

uninstall_gm_service() {
    stop_gm_service
    echo "[*] Deleting a service configuration file..."
    rm -f "$GM_SERVICE_FILE" || {
        echo "[-] Error: Failed to delete service profile"
        exit 0
    }
    
    systemctl daemon-reload
    echo "[+] Service uninstalled"
    # echo "[+] 服务已卸载（日志文件保留在 $GM_ServiceLogDir）"
}

Process_Exit() {
    case $SignalType in
        SIGINT)
            EXIT_MSG="[-] Capture the Ctrl+C signal to exit"
            ;;
        SIGTERM)
            EXIT_MSG="[-] Capture the process being killed"
            ;;
        SIGHUP)
            EXIT_MSG="[-] Captured terminal connection exception"
            ;;
        *)
            EXIT_MSG="[-] Unknown signal"
            ;;
    esac
    exit 1
}

trap 'SignalType*SIGINT; Process_Exit' SIGINT
trap 'SignalType*SIGTERM; Process_Exit' SIGTERM
trap 'SignalType*SIGHUP; Process_Exit' SIGHUP

Set_Server_Port() {
    PORT="$1"
    echo "Update server port...${PORT}"
    check_port_occupied "$PORT"
    if [ -e "$GM_SERVICE_CONFIG_FILE" ]; then
        sed -i.bak -E "s/(\"http_port\"\s*:\s*\"):?[0-9]+(\")/\1${PORT}\2/" $GM_SERVICE_CONFIG_FILE
    else
        echo "[-] Configuration file not found, please reinstall..."
        exit 1
    fi
    Get_ServerPort
    restart_gm_service
}

uninstall_gm_deps() {
    # 删除文件位置
    rm -rf $DEPLOY_ROOT_DIR  || {
        echo "[-] Error: Failed to delete app dir"
        exit 0
    }
}

Uninstall_GM() {
    uninstall_gm_service
    uninstall_gm_deps
}


show_gm_help() {

    echo -e "\033[1mHow to use / 使用方法:\033[0m \033[33m$0\033[0m [Command / 命令]"
    echo -e "\033[1mCommand List / 命令列表:\033[0m"
    echo "------------------------------------------------------------------------"

    printf "  \033[34minit\033[0m        - %-40s %s\n" \
        "Initialize the service" \
        "- 初始化服务"

    printf "  \033[34msetport\033[0m     - %-40s %s\n" \
        "Update service port" \
        "- 更新服务端口"

    printf "  \033[34mport\033[0m        - %-40s %s\n" \
        "Get port" \
        "- 获取服务端口号"

    printf "  \033[34mstart\033[0m       - %-40s %s\n" \
        "Start service in damon" \
        "- 以守护方式启动服务"

    printf "  \033[34mrestart\033[0m     - %-40s %s\n" \
        "Restart service" \
        "- 重启服务"

    printf "  \033[34mstop\033[0m        - %-40s %s\n" \
        "Stop service" \
        "- 停止服务"

    printf "  \033[34mstatus\033[0m      - %-40s %s\n" \
        "Check service status" \
        "- 查看服务状态"

    printf "  \033[34menable\033[0m      - %-40s %s\n" \
        "Enable auto-start on boot" \
        "- 设置开机自启"
    
    printf "  \033[34mdisable\033[0m     - %-40s %s\n" \
        "Disable auto-start on boot" \
        "- 取消开机自启"

    printf "  \033[34muninstall\033[0m   - %-40s %s\n" \
        "Uninstall service" \
        "- 卸载服务"

    printf "  \033[34mhelp\033[0m        - %-40s %s\n" \
        "Show help information" \
        "- 显示帮助信息"

}

Start_Done(){
    # check server port
    # GM_SERVICE_CONFIG_FILE
    echo -e "※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※"
    echo -e ""
    echo -e "\033[32mCongratulations! Start successfully!\033[0m"
    echo -e "" 
    echo -e "※※※※※※※※※※※※※※※※※※※※※※※※GMSSH Info※※※※※※※※※※※※※※※※※※※※※※※※※※※※※"
    echo -e ""
    echo -e "[+][Cloud Server] Please release it in the security group \033[31m$ServerPort\033[0m Port"
    echo -e "[+] \033[33mGM service public network access address：http://$PublicIP:$ServerPort\033[0m"
    echo -e "[+] \033[33mGM service local area network access address：http://$LocalIP:$ServerPort\033[0m"
}

main() {
    # 检查是否以root权限运行
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: Please run with root privileges（sudo）"
        exit 1
    fi

    if [ $# -eq 0 ]; then
        show_gm_help
        exit 1
    fi

    case "$1" in
        init)
            Start_Deploy
            ;;
        setport)
            Set_Server_Port "$2"
            ;;
        start)
            start_gm_service
            ;;
        restart)
            restart_gm_service
            ;;
        stop)
            stop_gm_service
            ;;
        port)
            Check_Server_Port
            ;;
        status)
            status_gm_service
            ;;
        enable)
            enable_gm_service
            ;;
        disable)
            disable_gm_service
            ;;
        uninstall)
            Uninstall_GM
            ;;
        help)
            show_gm_help
            ;;
        *)
            echo "Unknown command: $1"
            show_gm_help
            exit 1
            ;;
    esac
}
# ########################################################################
# 执行
# ########################################################################
main "$@"
