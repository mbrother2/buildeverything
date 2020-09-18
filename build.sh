#!/bin/bash
# Auto Install services on CentOS - Ubuntu
# Version: 1.0
# Author: mbrother

# Set variables
SCRIPT_NAME=$0
ALL_OPTIONS="$@"
GO_VERSION="go1.12.5.linux-amd64"
RANDOM_STRING=`date +%s | sha256sum | base64 | head -c 12`
BUILD_TMP="/root/buildeverything_${RANDOM_STRING}"
DIR=`pwd`
GITHUB_LINK="https://raw.githubusercontent.com/mbrother2/buildeverything/master"
MARIADB_MIRROR="http://sgp1.mirrors.digitalocean.com"
LOG_FILE="/var/log/buildeverything.log"
DEFAULT_DIR_WEB="/var/www/html"
REMI_DIR="/etc/opt/remi"
LSWS_DIR="/usr/local/lsws"
VHOST_DIR="/etc/nginx/conf.d"
SHOW_SERVICE=$(echo "Service Version Installed Running"
               echo "------- ------- --------- -------")

# List exclude mirrors
List_CentOS_epel=(mirror.xeonbd.com ftp.iij.ad.jp ftp.jaist.ac.jp)

# List support
List_OS=(CentOS Ubuntu)
List_CentOS=(6 7 8)
List_Ubuntu=(16.04 18.04 20.04)
List_MARIADB=(5.5 10.0 10.1 10.2 10.3 10.4 10.5)
List_NODEJS=(8.x 9.x 10.x 11.x 12.x 14.x)
List_BACKUP=(all gdrive rclone restic)
List_CACHE=(all memcached redis)
List_FTP=(proftpd pure-ftpd vsftpd)
List_WEB=(httpd openlitespeed nginx)
List_EXTRA=(all phpmyadmin vnstat)
List_SECURITY=(all acme_sh certbot clamav csf imunify)
List_STACK=(lamp lemp lomp)
List_SKIP_ACTION=(all no-update no-preinstall no-start)

# Default services & version
PMD_VERSION_MAX="5.0.2"
PMD_VERSION_COMMON="4.9.5"
RESTIC_VERSION="0.9.6"
DEFAULT_BACKUP_SERVICE="rclone"
DEFAULT_FTP_SERVER="pure-ftpd"
DEFAULT_PHP_VERSION="7.4"
DEFAULT_SQL_SERVER="10.4"
DEFAULT_WEB_SERVER="nginx"
DEFAULT_NODEJS="12.x"
DEFAULT_VNSTAT_VERSION="2.6"
DEFAULT_EXTRA_SERVICE="phpmyadmin"
DEFAULT_SECURITY_SERVICE="csf"

# Set colors
REMOVE='\e[0m'
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
WHITE='\e[39m'

# Check OS
_check_os(){
    OS_ARCH=`uname -m`
    if [ -f /etc/redhat-release ]
    then
        OS_NAME=`cat /etc/redhat-release | awk '{print $1}'`
        PKG_MANAGER="RPM"
        INSTALL_CM="yum"
        OS_VERSION=`rpm -E %centos`
        if [ "${OS_VERSION}" == "8" ]
        then
            List_PHP=(all 5.6 7.0 7.1 7.2 7.3 7.4)
        else
            List_PHP=(all 5.4 5.5 5.6 7.0 7.1 7.2 7.3 7.4)
        fi
    elif [ -f /usr/bin/lsb_release ]
    then
        OS_NAME=`lsb_release -is`
        OS_NAME_LOWER=`echo "${OS_NAME}" | awk '{print tolower($0)}'`
        OS_CODENAME=`lsb_release -cs | awk '{print tolower($0)}'`
        PKG_MANAGER="DEB"
        INSTALL_CM="apt"
        OS_VERSION=`lsb_release -rs`
        OS_VERSION_MIN=`echo "${OS_VERSION}" | sed 's/\.//'`
        if [ "${OS_NAME}" == "Ubuntu" ]
        then
            List_PHP=(all 5.6 7.0 7.1 7.2 7.3 7.4)
        fi
    fi
    _check_value_in_list "OS" "${OS_NAME}" "${List_OS[*]}"
    if [ -f /etc/redhat-release ]
    then
        _check_value_in_list "CentOS" "${OS_VERSION}" "${List_CentOS[*]}"
    elif [ -f /usr/bin/lsb_release ]
    then
        _check_value_in_list "Ubuntu" "${OS_VERSION}" "${List_Ubuntu[*]}"
    fi
}

# Trap press Ctrl + C
trap ctrl_c INT
ctrl_c(){
    echo ""
    _show_log -d -y " [WARN]" -w " You press Ctrl + C. Exit!"
    _exit_build 0
}

_exit_build(){
    rm -rf ${BUILD_TMP}
    exit $1
}

# Check user root
_check_user_root(){
    if [ $EUID -ne 0 ]
    then
        echo -e "`date "+[ %d/%m/%Y %H:%M:%S ]"` ${RED}[FAIL]${REMOVE} You must be ${GREEN}root${REMOVE} to run build.sh, please switch to root user then run again!"
        exit 1
    fi
}

# Print log
_print_log(){
    if [ ${SUM_ARG} -eq ${OPTIND} ]
    then
        printf "$1${OPTARG}${REMOVE}""\n" | tee -a ${LOG_FILE}
    else
        printf "$1${OPTARG}${REMOVE}" | tee -a ${LOG_FILE}
    fi
}

# Show log
_show_log(){
    OPTIND=1
    SUM_ARG=$(($#+1))
    while getopts 'r:g:y:w:d' OPTION
    do
        case ${OPTION} in
            d)  _print_log "`date "+[ %d/%m/%Y %H:%M:%S ]"`" ;;
            r)  _print_log "${RED}" ;;
            g)  _print_log "${GREEN}" ;;
            y)  _print_log "${YELLOW}" ;;
            w)  _print_log "${WHITE}" ;;
        esac
    done
}

# Check network
_check_network(){
    _show_log -d -g " [INFO]" -w " Cheking network..."
    curl -sI raw.githubusercontent.com >/dev/null
    if [ $? -eq 0 ]
    then
        _show_log -d -g " [INFO]" -w " Connect Github successful!"
    else
        _show_log -d -r " [FAIL]" -w " Can not connect to Github file, please check your network. Exit!"
        _exit_build 1
    fi
}

# Start time
_start_install(){
    TIME_BEGIN=`date +%s`
    echo "---" >> ${LOG_FILE}
    echo -e "$(date "+[ %d/%m/%Y %H:%M:%S ]") ${GREEN}[INFO]${REMOVE} Run command: ${RED}${SCRIPT_NAME} ${ALL_OPTIONS}${REMOVE}" >> ${LOG_FILE}
}

# End time
_end_install(){
    TIME_END=`date +%s`
    TIME_RUN=`date -d@$(( ${TIME_END} - ${TIME_BEGIN} )) -u +%Hh%Mm%Ss`
    _show_log -d -g " [INFO]" -w " Run time: ${TIME_RUN}"
    if [ ! -z "${SHOW_INFO}" ]
    then
        echo "${SHOW_INFO}"
    fi
    echo ""
    echo "---"
    echo "Ensure all services are installed and running."
    echo ""
    echo "${SHOW_SERVICE}" | column -t
    _exit_build 0
}

# Create necessary directory
_create_dir(){
    for i in ${DEFAULT_DIR_WEB} ${BUILD_TMP}
    do
        if [ ! -d $i ]
        then
            mkdir -p $i
        fi
    done
}

# Check if cPanel, DirectAdmin, Plesk has installed before
_check_control_panel(){
    _show_log -d -g " [INFO]" -w " Checking if cPanel, DirectAdmin, Plesk has installed before..."
    if [ -f /usr/local/cpanel/cpanel ]
    then
        _show_log -d -r " [FAIL]" -w " Detected cPanel is installed on this server. Please use minimal OS without any control panel to use buildmce !"
        _exit_build 1
    elif [ -f /usr/local/directadmin/custombuild/build ]
    then
        _show_log -d -r " [FAIL]" -w " Detected DirectAdmin is installed on this server. Please use minimal OS without any control panel to use buildmce !"
        _exit_build 1
    elif [ -f /usr/local/psa/version ]
    then
        _show_log -d -r " [FAIL]" -w " Detected Plesk is installed on this server. Please use minimal OS without any control panel to use buildmce !"
        _exit_build 1
    else
        _show_log -d -g " [INFO]" -w " No control panel detected. Continue..."
    fi
}

# Check option in a list
_check_value_in_list(){
    NAME=$1
    VALUE=$2
    List_VALUE=($3)
    false
    for i_CHECK_VALUE in ${List_VALUE[*]}
    do
        if [ "${i_CHECK_VALUE}" == "${VALUE}" ]
        then
            true
            break
        else
            false
        fi
    done
    if [ $? -ne 0 ]
    then
        _show_log -d -r " [FAIL]" -w " Not support $1:" -r " $2" -w ". Only support: $(echo ${List_VALUE[*]} | sed 's/ /|/g')"
        _exit_build 1
    fi
}

# Check exclude service
_check_exclude(){
    VAR=$1
    if [ ! -z "${EXCLUDE_SERVICE}" ]
    then
        CHECK_EXCLUDE=`echo "${EXCLUDE_SERVICE[@]}" | tr ' ' '\n' | grep -c "^$4$3$"`
        if [ ${CHECK_EXCLUDE} -ne 0 ]
        then
            eval "$VAR"=\( "${2/$3/}" \)
        fi
    fi
}

# Get options
_get_option(){
    if [ -z $4 ]
    then
        _show_log -d -r " [FAIL]" -w " Missing argument for option ${RED}$2${REMOVE}. Exit!"
        _exit_build 1
    else
        if [ "$1" == "single" ]
        then
            eval "$3"="$4"
        elif [ "$1" == "multi" ]
        then
            eval "$3"+=\( $4 \)
        fi
    fi   
}

# Check installed service
_check_installed_service(){
    CHECK_SERVICE=`command -v $1`
    if [ "$2" == "new"  ]
    then
        if [ -z ${CHECK_SERVICE} ]
        then
            _show_log -d -r " [FAIL]" -w " Can not install $1. Exit"
            _exit_build 1
        else
            _show_log -d -g " [INFO]" -w " Install $1 sucessful!"
        fi
    else
        if [ -z ${CHECK_SERVICE} ]
        then
            _show_log -d -r " [FAIL]" -w " $1 is not installed!"
            return 1
        else
            _show_log -d -g " [INFO]" -w " $1 is installed!"
            return 0
        fi
    fi
}

# Show Yes or No
_yes_no(){
    if [ ${1} -eq 2 ]
    then
        echo ""
    elif [ ${1} -eq 1 ]
    then
        echo "Yes"
    else
        echo "No"
    fi
}

# Detect web server
_detect_web_server(){
    if [ -z "${WEB_SERVER}" ]
    then
        _show_log -d -g " [INFO]" -w " Detecting web server..."
        if [ -z "${GET_WEB_SERVER}" ]
        then
            CHECK_HTTPD_RUNNING=`_check_service -r httpd`
            CHECK_NGINX_RUNNING=`_check_service -r nginx`
            CHECK_OLS_RUNNING=`_check_service -r litespeed`
            if [ ${CHECK_HTTPD_RUNNING} -eq 1 ]
            then
                _show_log -d -g " [INFO]" -w " Detected httpd running."
                WEB_SERVER="httpd"
            elif [ ${CHECK_NGINX_RUNNING} -eq 1 ]
            then
                _show_log -d -g " [INFO]" -w " Detected nginx running."
                WEB_SERVER="nginx"
            elif [ ${CHECK_OLS_RUNNING} -eq 1 ]
            then
                _show_log -d -g " [INFO]" -w " Detected openlitespeed running."
                WEB_SERVER="openlitespeed"
            else
                _show_log -d -g " [INFO]" -w " Can not detect web server is running!"
                echo ""
                echo "Do you want to install $1 for httpd or nginx or openlitespeed?"
                echo "1. httpd"
                echo "2. nginx"
                echo "3. openlitespeed"
                read -p "Your choice: " WEB_SERVER_CHOICE
                until [[ "${WEB_SERVER_CHOICE}" == 1 ]] || [[ "${WEB_SERVER_CHOICE}" == 2 ]] || [[ "${WEB_SERVER_CHOICE}" == 3 ]]
                do
                    echo "Please choose 1 or 2 or 3!"
                    read -p "Your choice: " WEB_SERVER_CHOICE
                done
                if [ ${WEB_SERVER_CHOICE} -eq 1 ]
                then
                    WEB_SERVER="httpd"
                elif [ ${WEB_SERVER_CHOICE} -eq 2 ]
                then
                    WEB_SERVER="nginx"
                else
                    WEB_SERVER="openlitespeed"
                fi
                _show_log -d -g " [INFO]" -w " You choose web server" -r " ${WEB_SERVER}"
            fi
        else
            WEB_SERVER=${GET_WEB_SERVER}
            _show_log -d -g " [INFO]" -w " Web server is ${GET_WEB_SERVER}."
        fi
    fi
}

# Detect service running at port
_detect_port_used(){
    _show_log -d -g " [INFO]" -w " Detecting service is running at port $2..."
    CHECK_PORT=`netstat -lntp | grep -e " 0.0.0.0:$2 " -e " 127.0.0.1:$2 " -e " :::$2 " | awk '{print $7}' | cut -d"/" -f2 | sed 's/://' | sed 's/.conf//' | uniq`
    if [ -z ${CHECK_PORT} ]
    then
        _show_log -d -g " [INFO]" -w " No service is running at port $2."
    else
        _show_log -d -g " [INFO]" -w " Detected ${CHECK_PORT} is running at port $2!"
        if [ "${CHECK_PORT}" != "$1" ]
        then
            _show_log -d -g " [INFO]" -w " Trying stop ${CHECK_PORT}..."
            if [ -f /bin/systemctl ]
            then
                systemctl stop ${CHECK_PORT}
            else
                service ${CHECK_PORT} stop
            fi
            CHECK_PORT_AGAIN=`netstat -lntp | grep -e " 0.0.0.0:$2 " -e " 127.0.0.1:$2 " -e " :::$2 " | awk '{print $7}' | cut -d"/" -f2 | sed 's/://' | sed 's/.conf//' | uniq`
            if [ ! -z ${CHECK_PORT_AGAIN} ]
            then
                _show_log -d -y " [WARN]" -w " Can not stop ${CHECK_PORT}!"
                CANNOT_STOP_PORT="CANNOT_STOP_PORT_$2"
                eval "$CANNOT_STOP_PORT"=1
            else
                _show_log -d -g " [INFO]" -w " Stop ${CHECK_PORT} sucessful!"
            fi
        fi    
    fi
}

#######################
# Check input options #
#######################

# Check informations
_check_info(){
    _show_log -d -g " [INFO]" -w " Checking input options..."
    if [ "${INSTALL_COMMON}" == "1" ]
    then
        GET_FTP_SERVER=${GET_FTP_SERVER:-$DEFAULT_FTP_SERVER}
        GET_PHP_VERSION=${GET_PHP_VERSION:-$DEFAULT_PHP_VERSION}
        GET_MARIADB=${GET_MARIADB:-$DEFAULT_SQL_SERVER}
        GET_NODEJS=${GET_NODEJS:-$DEFAULT_NODEJS}
        GET_WEB_SERVER=${GET_WEB_SERVER:-$DEFAULT_WEB_SERVER}
        EXTRA_SERVICE=( "${List_EXTRA[@]:1}" )
        SECURITY_SERVICE=( "${List_SECURITY[@]:1}" )
    elif [ ! -z "${GET_STACK}" ]
    then
        GET_FTP_SERVER=${GET_FTP_SERVER:-$DEFAULT_FTP_SERVER}
        GET_PHP_VERSION=${GET_PHP_VERSION:-$DEFAULT_PHP_VERSION}
        GET_MARIADB=${GET_MARIADB:-$DEFAULT_SQL_SERVER}
        if [ "${GET_STACK}" == "lamp" ]
        then
            GET_WEB_SERVER="httpd"
        elif [ "${GET_STACK}" == "lemp" ]
        then
            GET_WEB_SERVER="nginx"
        elif [ "${GET_STACK}" == "lomp" ]
        then
            GET_WEB_SERVER="openlitespeed"
        fi
        EXTRA_SERVICE=${EXTRA_SERVICE:-$DEFAULT_EXTRA_SERVICE}
        SECURITY_SERVICE=${SECURITY_SERVICE:-$DEFAULT_SECURITY_SERVICE}
    fi
    if [ ! -z "${SKIP_ACTION}" ]
    then
        if [ "${SKIP_ACTION}" == "all" ]
        then
            SKIP_ACTION=( "${List_SKIP_ACTION[@]:1}" )
            NO_UPDATE=1
            NO_PRE_INSTALL=1
            NO_START=1
        else
            for i_SKIP_ACTION in ${SKIP_ACTION[*]}
            do
                if [ "${i_SKIP_ACTION}" == "no-update" ]
                then
                    NO_UPDATE=1
                elif [ "${i_SKIP_ACTION}" == "no-preinstall" ]
                then
                    NO_PRE_INSTALL=1
                elif [ "${i_SKIP_ACTION}" == "no-start" ]
                then
                    NO_START=1
                fi
            done
        fi
        SHOW_OPTIONS=$(echo "Skip action    : ${SKIP_ACTION[*]}")
    fi
    if [ ! -z "${GET_BACKUP_SERVICE}" ]
    then
        if [ "${GET_BACKUP_SERVICE}" == "all" ]
        then
            GET_BACKUP_SERVICE=( "${List_BACKUP[@]:1}" )
        fi
        for i_GET_BACKUP_SERVICE in ${GET_BACKUP_SERVICE[*]}
        do
            _check_exclude GET_BACKUP_SERVICE "${GET_BACKUP_SERVICE[*]}" "${i_GET_BACKUP_SERVICE}"
        done
        if [ ! -z "${GET_BACKUP_SERVICE}" ]
        then
            SHOW_OPTIONS=$(echo "${SHOW_OPTIONS}"
                           echo "Backup         : ${GET_BACKUP_SERVICE[*]}")
            INSTALL_SERVICE+=("${GET_BACKUP_SERVICE[*]}")
        fi
    fi
    if [ ! -z "${GET_CACHE_SERVICE}" ]
    then
        if [ "${GET_CACHE_SERVICE}" == "all" ]
        then
            GET_CACHE_SERVICE=( "${List_CACHE[@]:1}" )
        fi
        for i_CACHE_SERVICE in ${GET_CACHE_SERVICE[*]}
        do
            _check_exclude GET_CACHE_SERVICE "${GET_CACHE_SERVICE[*]}" "${i_CACHE_SERVICE}"
        done
        if [ ! -z "${GET_CACHE_SERVICE}" ]
        then
            SHOW_OPTIONS=$(echo "${SHOW_OPTIONS}"
                           echo "Cache          : ${GET_CACHE_SERVICE[*]}")
            INSTALL_SERVICE+=("${GET_CACHE_SERVICE[*]}")
        fi
    fi
    if [ ! -z "${GET_FTP_SERVER}" ]
    then
        _check_exclude GET_FTP_SERVER "${GET_FTP_SERVER[*]}" "${GET_FTP_SERVER}"
        if [ ! -z "${GET_FTP_SERVER}" ]
        then
            SHOW_OPTIONS=$(echo "${SHOW_OPTIONS}"
                           echo "FTP server     : ${GET_FTP_SERVER}")
            INSTALL_SERVICE+=("${GET_FTP_SERVER}")
        fi
    fi
    if [ ! -z "${GET_PHP_VERSION}" ]
    then
        if [ "${GET_PHP_VERSION}" == "all" ]
        then
            GET_PHP_VERSION=( "${List_PHP[@]:1}" )
        fi
        for i_GET_PHP_VERSION in ${GET_PHP_VERSION[*]}
        do
            _check_exclude GET_PHP_VERSION "${GET_PHP_VERSION[*]}" "${i_GET_PHP_VERSION}" "php"
        done
        if [ ! -z "${GET_PHP_VERSION}" ]
        then
            SHOW_OPTIONS=$(echo "${SHOW_OPTIONS}"
                           echo "PHP version    : ${GET_PHP_VERSION[*]}")
            GET_PHP_VERSION_PREFIX=( "${GET_PHP_VERSION[@]/#/php}" )
            INSTALL_SERVICE+=("${GET_PHP_VERSION_PREFIX[*]}")
        fi
    fi
    if [ ! -z "${GET_NODEJS}" ]
    then
        _check_exclude GET_NODEJS "${GET_NODEJS[*]}" "${GET_NODEJS}" "nodejs"
        if [ ! -z "${GET_NODEJS}" ]
        then
            SHOW_OPTIONS=$(echo "${SHOW_OPTIONS}"
                           echo "Nodejs version : ${GET_NODEJS}")
            INSTALL_SERVICE+=("node")
        fi
    fi
    if [ ! -z "${GET_MARIADB}" ]
    then
        _check_exclude GET_MARIADB "${GET_MARIADB[*]}" "${GET_MARIADB}" "mariadb"
        if [ ! -z "${GET_MARIADB}" ]
        then
            SHOW_OPTIONS=$(echo "${SHOW_OPTIONS}"
                           echo "MariaDB version: ${GET_MARIADB}")
            INSTALL_SERVICE+=("mariadb")
        fi
    fi
    if [ ! -z "${GET_WEB_SERVER}" ]
    then
        _check_exclude GET_WEB_SERVER "${GET_WEB_SERVER[*]}" "${GET_WEB_SERVER}"
        if [ ! -z "${GET_WEB_SERVER}" ]
        then
            SHOW_OPTIONS=$(echo "${SHOW_OPTIONS}"
                           echo "Web server     : ${GET_WEB_SERVER}")
            INSTALL_SERVICE+=("${GET_WEB_SERVER}")
        fi
    fi
    if [ ! -z "${EXTRA_SERVICE}" ]
    then
        if [ "${EXTRA_SERVICE}" == "all" ]
        then
            EXTRA_SERVICE=( "${List_EXTRA[@]:1}" )
        fi
        for i_EXTRA_SERVICE in ${EXTRA_SERVICE[*]}
        do
            _check_exclude EXTRA_SERVICE "${EXTRA_SERVICE[*]}" "${i_EXTRA_SERVICE}"
        done
        if [ ! -z "${EXTRA_SERVICE}" ]
        then
            SHOW_OPTIONS=$(echo "${SHOW_OPTIONS}"
                           echo "Extra service  : ${EXTRA_SERVICE[*]}")
            INSTALL_SERVICE+=("${EXTRA_SERVICE[*]}")
        fi
    fi
    if [ ! -z "${SECURITY_SERVICE}" ]
    then
        if [ "${SECURITY_SERVICE}" == "all" ]
        then
            SECURITY_SERVICE=( "${List_SECURITY[@]:1}" )
        fi
        for i_SECURITY_SERVICE in ${SECURITY_SERVICE[*]}
        do
            _check_exclude SECURITY_SERVICE "${SECURITY_SERVICE[*]}" "${i_SECURITY_SERVICE}"
        done
        if [ ! -z "${SECURITY_SERVICE}" ]
        then
            SHOW_OPTIONS=$(echo "${SHOW_OPTIONS}"
                           echo "Security       : ${SECURITY_SERVICE[*]}")
            INSTALL_SERVICE+=("${SECURITY_SERVICE[*]}")
        fi
    fi
    _show_log -d -g " [INFO]" -w " Check input options sucessful!"
    echo ""
    if [ -z "${INSTALL_SERVICE}" ]
    then
        _show_log -d -y " [WARN]" -w " Nothing to install. Exit!"
        _exit_build 0
    fi
    echo "We will install following services:"
    echo "---"
    echo "${SHOW_OPTIONS}"
    if [ "${GET_BACKUP_SERVICE}" == "gdrive" ]
    then
        echo ""
        echo -e "${YELLOW}[WARNING]${REMOVE} gdrive project have not been updated in a long time. Recommend to use ${GREEN}rclone${REMOVE} to backup your data to Google Drive!"
    fi
    echo ""
    echo -e "If that is exactly what you need, please type ${GREEN}Yes${REMOVE} with caption ${GREEN}Y${REMOVE} to install or press ${RED}Ctrl + C${REMOVE} to cancel!"
    CHOICE_INSTALL="No"
    read -p "Your choice: " CHOICE_INSTALL
    while [ "${CHOICE_INSTALL}" != "Yes" ]
    do
        echo -e "Please type ${GREEN}Yes${REMOVE} with caption ${GREEN}Y${REMOVE} to install or press ${RED}Ctrl + C${REMOVE} to cancel!"
        read -p "Your choice: " CHOICE_INSTALL
    done
}

# Pre-install
_pre_install(){
    if [ "${NO_PRE_INSTALL}" != "1" ]
    then
        echo ""
        _show_log -d -g " [INFO]" -w " Installing require packages..."
        sleep 1
        if [ "${PKG_MANAGER}" == "RPM" ]
        then
            # Disable SELINUX, stop iptables( CentOS 6) or firewalld( CentOS 7) & disable on boot
            if [ -f /bin/systemctl ]
            then
                systemctl stop firewalld
                systemctl disable firewalld
            else
                service iptables stop
                chkconfig iptables off
            fi
    
            CHECK_SELINUX=`cat /etc/selinux/config | grep -c "^SELINUX=disabled"`
            if [ ${CHECK_SELINUX} -eq 0 ]
            then
                mv /etc/selinux/config /etc/selinux/config.orig
                cat /etc/selinux/config.orig | sed 's/^SELINUX/#SELINUX/g' > /etc/selinux/config
                echo "SELINUX=disabled" >> /etc/selinux/config
                echo "SELINUXTYPE=targeted" >> /etc/selinux/config
            fi

            # Install some require packages
            yum -y install epel-release
            rpm -Uvh http://rpms.remirepo.net/enterprise/remi-release-${OS_VERSION}.rpm
            sed -i "/^gpgkey=.*/a exclude = $(echo ${List_CentOS_epel[*]} | sed 's/ /, /g')" /etc/yum.repos.d/epel.repo
            yum -y install wget unzip net-tools pv socat bind-utils
        elif [ "${PKG_MANAGER}" == "DEB" ]
        then
            # Install some require packages
            apt-get -y install software-properties-common debconf-utils libwww-perl unzip net-tools
            if [ ${OS_VERSION_MIN} -lt 1804 ]
            then
                apt-get -y install gnupg-curl
            fi
        fi
        echo ""
        if [ $? -eq 0 ]
        then
            _show_log -d -g " [INFO]" -w " Install require packages sucessful!"
        else
            _show_log -d -g " [FAIL]" -w " Can not install require packages! Exit."
            _exit_build 1 
        fi
    fi
}

# Update system
_update_sys(){
    if [ "${NO_UPDATE}" != "1" ]
    then
        echo ""
        _show_log -d -g " [INFO]" -w " Updating system..."
        sleep 1
        if [ "${PKG_MANAGER}" == "RPM" ]
        then
            yum -y update
        elif [ "${PKG_MANAGER}" == "DEB" ]
        then
            apt-get update -y
            apt-get upgrade -y
            apt-get dist-upgrade -y
        fi
        echo ""
        _show_log -d -g " [INFO]" -w " Update system sucessful!"
    fi
}

####################
# Install services #
####################

# Install PHP
_install_php(){
    if [ ! -z "${GET_PHP_VERSION}" ]
    then
        echo ""
        _show_log -d -g " [INFO]" -w " Installing PHP..."
        sleep 1
        _detect_web_server php
        if [ "${PKG_MANAGER}" == "RPM" ]
        then
            if [ "${OS_VERSION}" == "8" ]
            then
                dnf config-manager --set-enabled PowerTools
            else
                yum -y install centos-release-scl-rh
                yum -y --enablerepo=centos-sclo-rh-testing install devtoolset-6-gcc-c++
            fi
            if [ "${WEB_SERVER}" == "openlitespeed" ]
            then
                PHP_PREFIX="lsphp"
                PHP_SUFFIX=""
                rpm -ivh http://rpms.litespeedtech.com/centos/litespeed-repo-1.1-1.el${OS_VERSION}.noarch.rpm            
            else
                PHP_PREFIX="php"
                PHP_SUFFIX="-php"
            fi
        
            for i_INSTALL_PHP in ${GET_PHP_VERSION[*]}
            do
                PHP_VERSION_MIN=`echo ${i_INSTALL_PHP} | sed 's/\.//'`
                echo ""
                _show_log -d -g " [INFO]" -w " Installing php${PHP_VERSION_MIN}..."
                if [ "${WEB_SERVER}" == "openlitespeed" ]
                then
                    PHP_ENABLE_REPO=""
                else
                    if [ "${OS_VERSION}" == "8" ]
                    then
                        PHP_ENABLE_REPO="--enablerepo=remi"
                    else
                        PHP_ENABLE_REPO="--enablerepo=remi-php${PHP_VERSION_MIN}"
                    fi
                fi
                yum -y ${PHP_ENABLE_REPO} install \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX} \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-curl \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-devel \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-exif \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-fileinfo \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-filter \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-gd \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-hash \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-imap \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-intl \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-json \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-mbstring \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-mcrypt \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-mysqlnd \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-session \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-soap \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-simplexml \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-xml \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-xmlrpc \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-xsl \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-zip \
                    ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-zlib 
    
                if [ "${WEB_SERVER}" == "openlitespeed" ]
                then
                    if [ -f /usr/local/lsws/lsphp${PHP_VERSION_MIN}/bin/lsphp ]
                    then
                        echo ""
                        _show_log -d -g " [INFO]" -w " Install php${PHP_VERSION_MIN} sucessful!"
                    else
                        _show_log -d -r " [FAIL]" -w " Can not install php${PHP_VERSION_MIN}. Exit"
                        _exit_build 1
                    fi  
                else
                    yum -y ${PHP_ENABLE_REPO} install ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-fpm 
                    if [[ "${PHP_VERSION_MIN}" == "54" ]] || [[ "${PHP_VERSION_MIN}" == "55" ]]
                    then
                        REMI_DIR="/etc/opt/remi"
                        if [ ! -d ${REMI_DIR} ]
                        then
                            mkdir ${REMI_DIR}
                        fi
                        ln -sf /opt/remi/php${PHP_VERSION_MIN}/root/etc ${REMI_DIR}/php${PHP_VERSION_MIN}
                    fi
                    echo ""
                    _check_installed_service "php${PHP_VERSION_MIN}" "new"   
                    sed -i "s/^listen =.*/listen = \/var\/run\/php${PHP_VERSION_MIN}.sock/" ${REMI_DIR}/php${PHP_VERSION_MIN}/php-fpm.d/www.conf
                    rm -f /var/run/php${PHP_VERSION_MIN}.sock
                    if [ "${NO_START}" != "1" ]
                    then
                        _restart_services php${PHP_VERSION_MIN}-php-fpm
                    fi
                    _start_on_boot php${PHP_VERSION_MIN}-php-fpm
                    CHECK_INSTALLED=`command -v php${PHP_VERSION_MIN} | wc -l`
                    if [ ${CHECK_INSTALLED} -ne 0 ]
                    then
                        CHECK_VERSION="${i_INSTALL_PHP}"
                    else
                        CHECK_VERSION="_"
                    fi
                    CHECK_RUNNING=`systemctl status php${PHP_VERSION_MIN}-php-fpm | grep -c "running"`
                    SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                                    echo "php${PHP_VERSION_MIN}-php-fpm ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})") 
                fi
            done
        elif [ "${PKG_MANAGER}" == "DEB" ]
        then
            if [ "${OS_NAME}" == "Ubuntu" ]
            then
                add-apt-repository -y ppa:ondrej/php
                apt-get update
                for i_INSTALL_PHP in ${GET_PHP_VERSION[*]}
                do
                    apt-get -y install php${i_INSTALL_PHP} \
                    php${i_INSTALL_PHP}-curl \
                    php${i_INSTALL_PHP}-exif \
                    php${i_INSTALL_PHP}-fileinfo \
                    php${i_INSTALL_PHP}-gd \
                    php${i_INSTALL_PHP}-imap \
                    php${i_INSTALL_PHP}-intl \
                    php${i_INSTALL_PHP}-json \
                    php${i_INSTALL_PHP}-mbstring \
                    php${i_INSTALL_PHP}-mysqlnd \
                    php${i_INSTALL_PHP}-soap \
                    php${i_INSTALL_PHP}-simplexml \
                    php${i_INSTALL_PHP}-xml \
                    php${i_INSTALL_PHP}-xmlrpc \
                    php${i_INSTALL_PHP}-xsl \
                    php${i_INSTALL_PHP}-zip
                done
            fi
        fi
    fi
}

# Install webserver
_install_web(){
    if [ ! -z "${GET_WEB_SERVER}" ]
    then
        echo ""
        _show_log -d -g " [INFO]" -w " Installing ${GET_WEB_SERVER}..."
        sleep 1
        _install_${GET_WEB_SERVER}
        echo ""
        _detect_port_used ${GET_WEB_SERVER} 80
        if [ -z "${CANNOT_STOP_PORT_80}" ]
        then
            if [ "${GET_WEB_SERVER}" == "openlitespeed" ]
            then
                sed -i 's/:8088$/:80/' ${LSWS_DIR}/conf/httpd_config.conf
            fi
            if [ "${NO_START}" != "1" ]
            then
                _restart_services ${GET_WEB_SERVER}
            fi
        fi
        _check_installed_service "${GET_WEB_SERVER}" "new"
        CHECK_INSTALLED=`command -v ${GET_WEB_SERVER} | wc -l`
        if [ ${CHECK_INSTALLED} -ne 0 ]
        then
            if [ "${GET_WEB_SERVER}" == "httpd" ]
            then
                CHECK_VERSION=`httpd -v | grep version | awk '{print $3}' | cut -d'/' -f2`
            elif [ "${GET_WEB_SERVER}" == "nginx" ]
            then
                CHECK_VERSION=`nginx -v 2>&1 | awk '{print $3}' | cut -d"/" -f2`
            elif [ "${GET_WEB_SERVER}" == "openlitespeed" ]
            then
                CHECK_VERSION=`/usr/local/lsws/bin/lshttpd -v | head -1 | awk '{print $1}' | cut -d'/' -f2`
            fi
        else
            CHECK_VERSION="_"
        fi
        CHECK_RUNNING=`systemctl status ${GET_WEB_SERVER} | grep -c "running"`
        SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                        echo "${GET_WEB_SERVER} ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})") 
    fi
}

# Install httpd
_install_httpd(){
    if [ "${PKG_MANAGER}" == "RPM" ]
    then
        yum -y install httpd
    elif [ "${PKG_MANAGER}" == "DEB" ]
    then
        apt-get install apache2
    fi
}
# Install nginx
_install_nginx(){
    if [ "${PKG_MANAGER}" == "RPM" ]
    then
        cat > "/etc/yum.repos.d/nginx.repo" <<EOF
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=0
enabled=1
module_hotfixes=true
EOF
        
        yum -y install nginx
    elif [ "${PKG_MANAGER}" == "DEB" ]
    then
        cd ${BUILD_TMP}
        wget https://nginx.org/keys/nginx_signing.key
        apt-key add nginx_signing.key
        cat >> "/etc/apt/sources.list" <<EOF
deb https://nginx.org/packages/${OS_NAME_LOWER}/ ${OS_CODENAME} nginx
deb-src https://nginx.org/packages/${OS_NAME_LOWER}/ ${OS_CODENAME} nginx        
EOF
        
        apt-get update
        apt-get -y install nginx
    fi
}
# Install OpenLiteSpeed
_install_openlitespeed(){
    if [ "${PKG_MANAGER}" == "RPM" ]
    then
        rpm -ivh http://rpms.litespeedtech.com/centos/litespeed-repo-1.1-1.el${OS_VERSION}.noarch.rpm
        yum -y install openlitespeed lsphp73-intl lsphp73-json lsphp73-devel lsphp73-soap lsphp73-xmlrpc lsphp73-zip
    elif [ "${PKG_MANAGER}" == "DEB" ]
    then
        cd ${BUILD_TMP}
        wget -O - http://rpms.litespeedtech.com/debian/enable_lst_debain_repo.sh | bash
        apt-get -y install openlitespeed lsphp73-intl
    fi
    ln -sf /usr/local/lsws/bin/openlitespeed /usr/local/bin/openlitespeed
}

# Install MariaDB
_install_mariadb(){    
    if [ ! -z "${GET_MARIADB}" ]
    then
        CHECK_SQL_SERVER=`_check_service -i "mysql"`
        if [ ${CHECK_SQL_SERVER} -ne 0 ]
        then
            echo ""
            _show_log -d -y " [WARN]" -w " MariaDB installed. Do not install new!"
        else
            echo ""
            _show_log -d -g " [INFO]" -w " Installing MariaDB..."
            sleep 1
            if [ "${PKG_MANAGER}" == "RPM" ]
            then
                # Check yum.mariadb.org
                HOST="yum.mariadb.org"
                if ping -c 1 -w 1 ${HOST} > /dev/null
                then
                    if [ "${OS_ARCH}" == "x86_64" ]
                    then
                        OS_ARCH1="amd64"
                    elif [ "${OS_ARCH}" == "i686" ]
                    then
                        OS_ARCH1="x86"
                    fi
                    cat > "/etc/yum.repos.d/MariaDB.repo" <<EOF
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/${GET_MARIADB}/centos${OS_VERSION}-${OS_ARCH1}
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF
                    if [ "${OS_VERSION}" == "8" ]
                    then
                        yum -y install boost-program-options
                        yum -y install MariaDB-server MariaDB-client --disablerepo=AppStream
                    else
                        yum -y install MariaDB-server MariaDB-client
                    fi
                else
                    _show_log -d -r " [FAIL]" -w " Can not connect to yum.mariadb.org! Exit"
                    _exit_build 1
                fi
            elif [ "${PKG_MANAGER}" == "DEB" ]
            then
                MARIADB_VERSION_MIN=`echo ${GET_MARIADB} | sed 's/\.//'`
                if [ ${MARIADB_VERSION_MIN} -lt 104 ]
                then
                    SQLPASS=`date +%s | sha256sum | base64 | head -c 12`
                    echo "maria-db-${GET_MARIADB} mysql-server/root_password password ${SQLPASS}" | debconf-set-selections
                    echo "maria-db-${GET_MARIADB} mysql-server/root_password_again password ${SQLPASS}" | debconf-set-selections
                fi
                apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc'
                add-apt-repository "deb [arch=amd64,arm64,i386,ppc64el] ${MARIADB_MIRROR}/mariadb/repo/${GET_MARIADB}/${OS_NAME_LOWER} ${OS_CODENAME} main"
                apt-get -y update
                apt-get -y install mariadb-server
            fi
            echo ""
            _check_installed_service "mysql" "new"
            CHECK_MARIADB=`mysql -V | grep MariaDB | wc -l`
            if [ ${CHECK_MARIADB} = 1 ]
            then
                if [ "${GET_MARIADB}" == "10.4" ]
                then
                    MYSQL="mariadb"
                else
                    MYSQL="mysql"
                fi
            else
                MYSQL="mysqld"
            fi
            if [ "${NO_START}" != "1" ]
            then
                _restart_services ${MYSQL}
            fi
            _start_on_boot ${MYSQL}
        fi
        CHECK_INSTALLED=`command -v mysql | wc -l`
        if [ ${CHECK_INSTALLED} -ne 0 ]
        then
            CHECK_VERSION=`mysql -V | awk '{print $5}' | cut -d"-" -f 1 | sed 's/,//'`
            SHOW_INFO=$( echo "${SHOW_INFO}"
                         echo "---"
                         echo -e "${RED}[IMPORTANT]${REMOVE} You should run command ${GREEN}mysql_secure_installation${REMOVE} to set Mariadb root's password and secure your sql server!" )
        else
            CHECK_VERSION="_"
        fi
        CHECK_RUNNING=`systemctl status mysql | grep -c "running"`
        SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                        echo "mariadb ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
    fi
}

# Install phpMyAdmin
_install_phpmyadmin(){
    echo ""
    _show_log -d -g " [INFO]" -w " Installing phpMyAdmin..."
    sleep 1
    if [ "${GET_PHP_VERSION}" == "all" ]
    then
        PMD_VERSION=${PMD_VERSION_MAX}
    else
        _detect_web_server phpMyAdmin
        _show_log -d -g " [INFO]" -w " Detecting PHP version installed..."
        if [ "${WEB_SERVER}" != "openlitespeed" ]
        then
            if [ "${PKG_MANAGER}" == "RPM" ]
            then
                PHP_PREFIX="php"
                PHP_DIR="${REMI_DIR}"
            elif [ "${PKG_MANAGER}" == "DEB" ]
            then
                PHP_PREFIX=""
                PHP_DIR="/etc/php"
            fi
        else
            PHP_PREFIX="lsphp"
            PHP_DIR="${LSWS_DIR}"
        fi
        CHECK_PHP_INSTALLED=`ls -1 ${PHP_DIR} | wc -l`
        if [ ${CHECK_PHP_INSTALLED} -eq 0 ]
        then
            _show_log -d -r " [FAIL]" -w " Can not detect PHP version! Exit"
            _exit_build 1
        else
            if [ "${PKG_MANAGER}" == "RPM" ]
            then
                LIST_PHP_INSTALLED=`ls -1 ${PHP_DIR} | grep "${PHP_PREFIX}[0-9][0-9]" | sed "s/${PHP_PREFIX}//" | sed ':a;N;$!ba;s/\n/ /g'`
            elif [ "${PKG_MANAGER}" == "DEB" ]
            then
                LIST_PHP_INSTALLED=`ls -1 ${PHP_DIR} | grep "[0-9]\.[0-9]" | sed 's/\.//g' | sed ':a;N;$!ba;s/\n/ /g'`
            fi
            _show_log -d -g " [INFO]" -w " List PHP version: ${LIST_PHP_INSTALLED}"
        fi
        for i_INSTALL_PHPMYADMIN in $(echo ${LIST_PHP_INSTALLED})
        do
            if [ ${i_INSTALL_PHPMYADMIN} -eq 54 ]
            then
                PMD_VERSION="4.0.10.20"
            elif [ ${i_INSTALL_PHPMYADMIN} -lt 71 ]
            then
                PMD_VERSION=${PMD_VERSION_COMMON}
            else
                PMD_VERSION=${PMD_VERSION_MAX}
            fi
        done
        PHP_VERSION_PMD=`awk "BEGIN {printf \"%.1f\n\", ${i_INSTALL_PHPMYADMIN} / 10}"`
        _show_log -d -g " [INFO]" -w " Highest PHP version is ${PHP_VERSION_PMD}. We will install phpMyAdmin ${PMD_VERSION}"
        cd ${DIR}
        wget -O phpmyadmin.tar.gz https://files.phpmyadmin.net/phpMyAdmin/${PMD_VERSION}/phpMyAdmin-${PMD_VERSION}-all-languages.tar.gz
        for i_PHPMYADMIN_DIR in ${DIR}/phpmyadmin ${DIR}/phpMyAdmin-${PMD_VERSION}-all-languages ${DEFAULT_DIR_WEB}/phpmyadmin
        do
            if [ -e ${i_PHPMYADMIN_DIR} ]
            then
                rm -rf ${i_PHPMYADMIN_DIR}
            fi
        done
        tar -xf phpmyadmin.tar.gz
        rm -f phpmyadmin.tar.gz
        mv phpMyAdmin-${PMD_VERSION}-all-languages ${DEFAULT_DIR_WEB}/phpmyadmin
        mv ${DEFAULT_DIR_WEB}/phpmyadmin/config.sample.inc.php ${DEFAULT_DIR_WEB}/phpmyadmin/config.inc.php
    fi
    echo ""
    _show_log -d -g " [INFO]" -w " Install phpMyadmin sucessful!"
    if [ -f ${DEFAULT_DIR_WEB}/phpmyadmin/config.inc.php ]
    then
        CHECK_INSTALLED="1"
        CHECK_VERSION="${PMD_VERSION}"
        SHOW_INFO=$( echo "${SHOW_INFO}"
                     echo "---"
                     echo -e "phpmyadmin locate here: ${DEFAULT_DIR_WEB}" )
    else
        CHECK_INSTALLED="0"
        CHECK_VERSION="_"
    fi
    CHECK_RUNNING="2"
    SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                    echo "phpmyadmin ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
    CHECK_MARIADB=`mysql -V | grep MariaDB | wc -l`
}

# Install FTP
_install_ftp(){
    if [ ! -z "${GET_FTP_SERVER}" ]
    then
        echo ""
        _show_log -d -g " [INFO]" -w " Installing ${GET_FTP_SERVER}..."
        sleep 1
        if [ "${PKG_MANAGER}" == "RPM" ]
        then
            yum -y install ${GET_FTP_SERVER}
        elif [ "${PKG_MANAGER}" == "DEB" ]
        then
            apt-get -y install ${GET_FTP_SERVER}
        fi
        echo ""
        _detect_port_used ${GET_FTP_SERVER} 21
        if [[ -z "${CANNOT_STOP_PORT_21}" ]] && [[ "${NO_START}" != "1" ]]
        then
            _restart_services ${GET_FTP_SERVER}
        fi
        _check_installed_service "${GET_FTP_SERVER}" "new"
        CHECK_INSTALLED=`command -v ${GET_FTP_SERVER} | wc -l`
        if [ ${CHECK_INSTALLED} -ne 0 ]
        then
            if [ "$GET_FTP_SERVER" == "proftpd" ]
            then
                CHECK_VERSION=`proftpd -v | awk '{print $3}'`
            elif [ "$GET_FTP_SERVER" == "pure-ftpd" ]
            then
                CHECK_VERSION=`pure-ftpd --help | head -1 | awk '{print $2}' | sed s/v//`
            elif [ "$GET_FTP_SERVER" == "vsftpd" ]
            then
                CHECK_VERSION=`vsftpd -v | awk '{print $3}'`
            fi
        else
            CHECK_VERSION="_"
        fi
        CHECK_RUNNING=`systemctl status ${GET_FTP_SERVER} | grep -c "running"`
        SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                        echo "${GET_FTP_SERVER} ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
    fi
}

# Install csf
_install_csf(){
    echo ""
    _show_log -d -g " [INFO]" -w " Installing csf..."
    sleep 1
    if [ "${PKG_MANAGER}" == "RPM" ]
    then
        yum -y install perl-libwww-perl perl-LWP-Protocol-https bind-utils
    fi
    cd ${BUILD_TMP}
    curl -o csf.tgz https://download.configserver.com/csf.tgz
    tar -xf csf.tgz
    cd csf
    sh install.sh
    if [ "${NO_START}" != "1" ]
    then
        csf -e
    fi
    echo ""
    _check_installed_service "csf" "new"
    CHECK_INSTALLED=`command -v csf | wc -l`
    if [ ${CHECK_INSTALLED} -ne 0 ]
    then
        CHECK_VERSION=`csf -v | head -1 | awk '{print $2}' | sed 's/v//'`
    else
        CHECK_VERSION="_"
    fi
    CHECK_RUNNING=`csf -l | head | wc -l`
    if [ ${CHECK_RUNNING} -eq 1 ]
    then
        CHECK_RUNNING=0
    else
        CHECK_RUNNING=1
    fi
    SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                    echo "csf ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
}

# Install & config ImunifyAV
_install_imunify(){
    echo ""
    _show_log -d -g " [INFO]" -w " Installing ImunifyAV..."
    if [ ! -d /etc/sysconfig/imunify360 ]
    then
        mkdir -p /etc/sysconfig/imunify360
    fi
    cat > /etc/sysconfig/imunify360/integration.conf <<EOF
[PATHS]
UI_PATH = /var/www/html/ImunifyAV

[paths]
ui_path = /var/www/html/ImunifyAV
EOF
    cd ${BUILD_TMP}
    wget https://repo.imunify360.cloudlinux.com/defence360/imav-deploy.sh
    bash imav-deploy.sh
    echo ""
    _check_installed_service "imunify-antivirus" "new"
    CHECK_INSTALLED=`command -v imunify-antivirus | wc -l`
    if [ ${CHECK_INSTALLED} -ne 0 ]
    then
        CHECK_VERSION=`imunify-antivirus version`
    else
        CHECK_VERSION="_"
    fi
    CHECK_RUNNING=`systemctl status imunify-antivirus | grep -c "running"`
    SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                    echo "imunify-antivirus ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
}

# Install certbot
_install_certbot(){
    echo ""
    _show_log -d -g " [INFO]" -w " Installing certbot..."
    if [ "${PKG_MANAGER}" == "RPM" ]
    then
        yum -y install certbot
    elif [ "${PKG_MANAGER}" == "DEB" ]
    then
        add-apt-repository -y ppa:certbot/certbot
        apt-get update
        apt-get -y install certbot
    fi
    echo ""
    _check_installed_service "certbot" "new"
    CHECK_INSTALLED=`command -v certbot | wc -l`
    if [ ${CHECK_INSTALLED} -ne 0 ]
    then
        CHECK_VERSION=`certbot --version 2>&1 | awk '{print $2}'`
    else
        CHECK_VERSION="_"
    fi
    CHECK_RUNNING="2"
    SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                    echo "certbot ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
}

# Install acme.sh
_install_acme_sh(){
    echo ""
    _show_log -d -g " [INFO]" -w " Installing acme.sh..."
    curl https://get.acme.sh | sh
    echo ""
    if [ -f /root/.acme.sh/acme.sh ]
    then
        _show_log -d -g " [INFO]" -w " Install acme.sh sucessful!"
        CHECK_VERSION=`sh /root/.acme.sh/acme.sh --version | tail -1 | sed 's/v//'`
        CHECK_INSTALLED="1"
        CHECK_RUNNING="2"
        SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                    echo "acme.sh ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
    else
        _show_log -d -g " [INFO]" -w " Can not install acme.sh! Exit"
        _exit_build 1
    fi
}

# Install memcached or redis
_install_memcached_redis(){
    SERVICE_NAME=$1
    echo ""
    _show_log -d -g " [INFO]" -w " Installing ${SERVICE_NAME}..."
    _detect_web_server "php ${SERVICE_NAME} extension"
    if [ "${WEB_SERVER}" != "nginx" ]
    then
        PHP_PREFIX="lsphp"
        PHP_DIR="${LSWS_DIR}"
        PHP_SUFFIX="-pecl"
    else        
        PHP_PREFIX="php"
        PHP_DIR="${REMI_DIR}"
        PHP_SUFFIX="-php"
    fi
    if [ -z "${GET_PHP_VERSION}" ]
    then
        _show_log -d -g " [INFO]" -w " Detecting PHP version installed..."
        CHECK_PHP_INSTALLED=`ls -1 ${PHP_DIR} | wc -l`
        if [ ${CHECK_PHP_INSTALLED} -eq 0 ]
        then
            _show_log -d -r " [FAIL]" -w " Can not detect PHP version! Exit"
            _exit_build 1
        else
            _show_log -d -g " [INFO]" -w " List PHP version: $(ls -1 ${PHP_DIR} | grep "${PHP_PREFIX}[0-9][0-9]" | sed "s/.*php//" | sed ':a;N;$!ba;s/\n/,/g')"
        fi
        PHP_VERSION_MCD=$(ls -1 ${PHP_DIR} | grep "${PHP_PREFIX}[0-9][0-9]" | sed "s/${PHP_PREFIX}//")
    else
        PHP_VERSION_MCD=${GET_PHP_VERSION}
    fi
    if [ "${SERVICE_NAME}" == "memcached" ]
    then
        if [ "${PKG_MANAGER}" == "RPM" ]
        then
            yum -y install memcached libmemcached
        fi
    else
        if [ "${PKG_MANAGER}" == "RPM" ]
        then
            yum -y install redis
        fi
    fi
    for i_INSTALL_MEMCACHED_REDIS in $(echo ${PHP_VERSION_MCD})
    do
        echo ""
        PHP_VERSION_MIN=`echo ${i_INSTALL_MEMCACHED_REDIS} | sed 's/\.//'`
        _show_log -d -g " [INFO]" -w " Installing php ${SERVICE_NAME} extension for php${PHP_VERSION_MIN}..."
        if [ "${WEB_SERVER}" == "nginx" ]
        then
            if [ "${OS_VERSION}" == "8" ]
            then
                PHP_ENABLE_REPO="remi"
            else
                PHP_ENABLE_REPO="remi-php${PHP_VERSION_MIN}"
            fi
            PHP_BIN="php${PHP_VERSION_MIN}"
        else
            PHP_ENABLE_REPO="litespeed"
            PHP_BIN="${LSWS_DIR}/lsphp${PHP_VERSION_MIN}/bin/php"
        fi
        yum -y --enablerepo=${PHP_ENABLE_REPO} install ${PHP_PREFIX}${PHP_VERSION_MIN}${PHP_SUFFIX}-${SERVICE_NAME}
        CHECK_PHP_SERVICE=`${PHP_BIN} -m | grep -c "^${SERVICE_NAME}$"`
        if [ ${CHECK_PHP_SERVICE} -ne 0 ]
        then
            _show_log -d -g " [INFO]" -w " Install php ${SERVICE_NAME} extension for php${PHP_VERSION_MIN} sucessful!"
        else
            _show_log -d -r " [FAIL]" -w " Can not install php ${SERVICE_NAME} extension for php${PHP_VERSION_MIN}"
        fi
    done
    if [ "${SERVICE_NAME}" == "memcached" ]
    then
        _check_installed_service "memcached" "new"
    else
        _check_installed_service "redis-server" "new"
    fi
    if [ "${NO_START}" != "1" ]
    then
        _restart_services ${SERVICE_NAME}
    fi
}
# Install memcached
_install_memcached(){
    _install_memcached_redis memcached
    CHECK_INSTALLED=`command -v memcached | wc -l`
    if [ ${CHECK_INSTALLED} -ne 0 ]
    then
        CHECK_VERSION=`memcached -h | head -1 | awk '{print $2}'`
    else
        CHECK_VERSION="_"
    fi
    CHECK_RUNNING=`systemctl status memcached | grep -c "running"`
    SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                    echo "memcached ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
}
# Install redis
_install_redis(){
    _install_memcached_redis redis
    CHECK_INSTALLED=`command -v redis-server | wc -l`
    if [ ${CHECK_INSTALLED} -ne 0 ]
    then
        CHECK_VERSION=`redis-server -v | awk '{print $3}' | cut -d'=' -f2`
    else
        CHECK_VERSION="_"
    fi
    CHECK_RUNNING=`systemctl status redis | grep -c "running"`
    SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                    echo "redis ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
}

# Install Node.js
_install_nodejs(){
    if [ ! -z "${GET_NODEJS}" ]
    then
        CHECK_NODEJS=`node -v 2>/dev/null`
        if [ ! -z ${CHECK_NODEJS} ]
        then
            echo ""
            _show_log -d -y " [WARN]" -w " Node.js ${CHECK_NODEJS} installed. Do not install new!"
            NOT_CONFIG_NODEJS=1
        else
            _show_log -d -g " [INFO]" -w " Installing Node.js ${GET_NODEJS}..."
            if [ "${PKG_MANAGER}" == "RPM" ]
            then
                yum -y install make gcc-c++
                curl -sL https://rpm.nodesource.com/setup_${GET_NODEJS} | bash -
                yum clean metadata
                yum -y install nodejs
            elif [ "${PKG_MANAGER}" == "DEB" ]
            then
                curl -sL https://deb.nodesource.com/setup_${GET_NODEJS} | bash -
                apt-get -y install nodejs
            fi
            _check_installed_service "node" "new"
            CHECK_INSTALLED=`command -v node | wc -l`
            if [ ${CHECK_INSTALLED} -ne 0 ]
            then
                CHECK_VERSION=`node -v | sed 's/v//'`
            else
                CHECK_VERSION="_"
            fi
            CHECK_RUNNING="2"
            SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                            echo "nodejs ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
        fi
    fi
}

# Install vnstat
_install_vnstat(){
    echo ""
    _show_log -d -g " [INFO]" -w " Installing vnstat..."
    if [ "${PKG_MANAGER}" == "RPM" ]
    then
        yum -y install make gcc sqlite-devel
    elif [ "${PKG_MANAGER}" == "DEB" ]
    then
        apt-get -y install make gcc libsqlite3-dev
    fi
    cd ${BUILD_TMP}
    curl -o vnstat-${DEFAULT_VNSTAT_VERSION}.tar.gz https://humdi.net/vnstat/vnstat-${DEFAULT_VNSTAT_VERSION}.tar.gz
    tar -xf vnstat-${DEFAULT_VNSTAT_VERSION}.tar.gz
    cd vnstat-${DEFAULT_VNSTAT_VERSION}
    ./configure
    make
    make install
    _check_installed_service "vnstat" "new"
    CHECK_INSTALLED=`command -v vnstat | wc -l`
    if [ ${CHECK_INSTALLED} -ne 0 ]
    then
        CHECK_VERSION=`vnstat -v | awk '{print $2}'`
    else
        CHECK_VERSION="_"
    fi
    CHECK_RUNNING="2"
    SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                    echo "vnstat ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
}

# Install ClamAV
_install_clamav(){
    echo ""
    _show_log -d -g " [INFO]" -w " Installing ClamAV..."
    if [ "${PKG_MANAGER}" == "RPM" ]
    then
        yum -y install clamav-server clamav-data clamav-update clamav-filesystem clamav clamav-scanner-systemd clamav-devel clamav-lib clamav-server-systemd
    elif [ "${PKG_MANAGER}" == "DEB" ]
    then
        apt-get -y install clamav clamav-daemon
    fi
    if [ "${NO_START}" != "1" ]
    then
        sed -i 's/^#LocalSocket /LocalSocket /' /etc/clamd.d/scan.conf
        _restart_services "clamd@scan"
        freshclam
    fi
    _start_on_boot "clamd@scan"
    _check_installed_service "clamd" "new"
    CHECK_INSTALLED=`command -v clamd | wc -l`
    if [ ${CHECK_INSTALLED} -ne 0 ]
    then
        CHECK_VERSION=`clamd --version | awk '{print $2}' | cut -d'/' -f1`
    else
        CHECK_VERSION="_"
    fi
    CHECK_RUNNING=`systemctl status clamd@scan | grep -c "running"`
    SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                    echo "clamd@scan ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
}

# Install backup
_install_backup(){
    if [ ! -z "${GET_BACKUP_SERVICE}" ]
    then
        for i_GET_BACKUP_SERVICE in ${GET_BACKUP_SERVICE[*]}
        do
            echo ""
            _show_log -d -g " [INFO]" -w " Installing ${i_GET_BACKUP_SERVICE}..."
            _install_${i_GET_BACKUP_SERVICE}
            _check_installed_service "${i_GET_BACKUP_SERVICE}" "new"
        done
    fi
}

# Install gdrive
_install_gdrive(){
    _show_log -d -g " [INFO]" -w " Installing git package..."
    if [ "${PKG_MANAGER}" == "RPM" ]
    then
        yum -y install git
    elif [ "${PKG_MANAGER}" == "DEB" ]
    then
        apt-get -y install git
    fi
    _check_installed_service "git" "new"
    cd ${BUILD_TMP}
    _show_log -d -g " [INFO]" -w " Downloading go ${GO_VERSION} from Google..."
    curl -o ${GO_VERSION}.tar.gz https://dl.google.com/go/${GO_VERSION}.tar.gz
    _show_log -d -g " [INFO]" -w " Extracting go lang..."
    tar -xf ${GO_VERSION}.tar.gz
    _show_log -d -g " [INFO]" -w " Cloning gdrive project from Github..."
    rm -rf gdrive
    git clone https://github.com/gdrive-org/gdrive.git
    _show_log -d -g " [INFO]" -w " Build your own gdrive!"
    echo ""
    echo "Read more: https://github.com/mbrother2/backuptogoogle/wiki/Create-own-Google-credential-step-by-step"
    read -p " Your Google API client_id: " GG_CLIENT_ID
    read -p " Your Google API client_secret: " GG_CLIENT_SECRET
    sed -i "s#^const ClientId =.*#const ClientId = \"${GG_CLIENT_ID}\"#g" ${BUILD_TMP}/gdrive/handlers_drive.go
    sed -i "s#^const ClientSecret =.*#const ClientSecret = \"${GG_CLIENT_SECRET}\"#g" ${BUILD_TMP}/gdrive/handlers_drive.go
    echo ""
    _show_log -d -g " [INFO]" -w " Building gdrive..."
    cd ${BUILD_TMP}/gdrive
    ${BUILD_TMP}/go/bin/go get github.com/prasmussen/gdrive
    ${BUILD_TMP}/go/bin/go build -ldflags '-w -s'
    if [ $? -ne 0 ]
    then
        _show_log -d -r " [FAIL]" -w " Can not build gdrive. Exit"
        _exit_build 1
    else
        _show_log -d -g " [INFO]" -w " Build gdrive successful. gdrive bin locate here:" -g " /usr/local/sbin/gdrive"
    fi
    mv ${BUILD_TMP}/gdrive/gdrive /usr/local/sbin/gdrive
    rm -rf ${DIR}/go
    chmod 755 /usr/local/sbin/gdrive
    SHOW_INFO=$( echo "${SHOW_INFO}"
                 echo "---"
                 echo -e "gdrive bin locate here: ${GREEN}/usr/local/sbin/gdrive${REMOVE}" )
    gdrive about
    if [ $? -ne 0 ]
    then
        _show_log -d -y " [WARN]" -w " Can not connect Google Drive with your credential, please check again!"
    fi
    CHECK_INSTALLED=`command -v gdrive | wc -l`
    if [ ${CHECK_INSTALLED} -ne 0 ]
    then
        CHECK_VERSION=`gdrive version | head -1 | awk '{print $2}'`
    else
        CHECK_VERSION="_"
    fi
    CHECK_RUNNING="2"
    SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                    echo "gdrive ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
}
# Install rclone
_install_rclone(){
    _show_log -d -g " [INFO]" -w  " Downloading rclone from homepage..."
    cd ${BUILD_TMP}
    curl -o rclone.zip https://downloads.rclone.org/rclone-current-linux-amd64.zip
    unzip -q rclone.zip -d rclone
    if [ $? -ne 0 ]
    then
        _show_log -d -r " [FAIL]" -w " Can not download rclone. Exit"
        _exit_build 1
    else
        _show_log -d -g " [INFO]" -w " Download rclone successful. rclone bin locate here:" -g " /usr/local/sbin/rclone"
    fi
    mv rclone/rclone-*-linux-amd64/rclone /usr/local/sbin/rclone
    chmod 755 /usr/local/sbin/rclone
    SHOW_INFO=$( echo "${SHOW_INFO}"
                 echo "---"
                 echo -e "rclone bin locate here: ${GREEN}/usr/local/sbin/rclone${REMOVE}" )
    echo ""
    echo "Read more: https://github.com/mbrother2/backuptogoogle/wiki/Create-own-Google-credential-step-by-step"
    read -p " Your Google API client_id: " GG_CLIENT_ID
    read -p " Your Google API client_secret: " GG_CLIENT_SECRET
    rclone config create drive drive config_is_local false scope drive client_id ${GG_CLIENT_ID} client_secret ${GG_CLIENT_SECRET}
    if [ $? -ne 0 ]
    then
        _show_log -d -y " [WARN]" -w " Can not connect Google Drive with your credential, please check again!"
    fi
    CHECK_INSTALLED=`command -v rclone | wc -l`
    if [ ${CHECK_INSTALLED} -ne 0 ]
    then
        CHECK_VERSION=`rclone --version | head -1 | awk '{print $2}' | sed 's/v//'`
    else
        CHECK_VERSION="_"
    fi
    CHECK_RUNNING="2"
    SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                    echo "rclone ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
}
# Install restic
_install_restic(){
    _show_log -d -g " [INFO]" -w  " Downloading restic from github..."
    cd ${BUILD_TMP}
    wget -O restic.bz2 https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_amd64.bz2
    bzip2 -d restic.bz2
    if [ $? -ne 0 ]
    then
        _show_log -d -r " [FAIL]" -w " Can not download restic. Exit"
        _exit_build 1
    else
        _show_log -d -g " [INFO]" -w " Download restic successful. restic bin locate here:" -g " /usr/local/sbin/restic"
    fi
    mv restic /usr/local/sbin/restic
    chmod 755 /usr/local/sbin/restic
    SHOW_INFO=$( echo "${SHOW_INFO}"
                 echo "---"
                 echo -e "restic bin locate here: ${GREEN}/usr/local/sbin/restic${REMOVE}" )
    CHECK_INSTALLED=`command -v restic | wc -l`
    if [ ${CHECK_INSTALLED} -ne 0 ]
    then
        CHECK_VERSION=`restic version | awk '{print $2}'`
    else
        CHECK_VERSION="_"
    fi
    CHECK_RUNNING="2"
    SHOW_SERVICE=$( echo "${SHOW_SERVICE}"
                    echo "restic ${CHECK_VERSION} $(_yes_no ${CHECK_INSTALLED}) $(_yes_no ${CHECK_RUNNING})")
}

# Restart service
_restart_services(){
    if [ -f /bin/systemctl ]
    then
        systemctl restart $1
    else
        service $1 restart
    fi
}

# Start service when boot
_start_on_boot(){
    if [ "${PKG_MANAGER}" == "RPM" ]
    then
        if [ -f /bin/systemctl ]
        then
            systemctl enable $1
        else
            chkconfig $1 on
        fi
    fi
}

# Check services after install
_check_service(){
    case $1 in
        -i) command -v $2 | wc -l ;;
        -r) pidof $2 | wc -l ;;
    esac
}

# Main install
_main_install(){
    _install_backup
    _install_ftp
    _install_php
    _install_nodejs
    _install_mariadb
    _install_web
    if [ ! -z "${EXTRA_SERVICE}" ]
    then
        for i_EXTRA_SERVICE in ${EXTRA_SERVICE[*]}
        do
            _install_${i_EXTRA_SERVICE}
        done
    fi
    if [ ! -z "${GET_CACHE_SERVICE}" ]
    then
        for i_CACHE_SERVICE in ${GET_CACHE_SERVICE[*]}
        do
            _install_${i_CACHE_SERVICE}
        done
    fi
    if [ ! -z "${SECURITY_SERVICE}" ]
    then
        for i_SECURITY_SERVICE in ${SECURITY_SERVICE[*]}
        do
            _install_${i_SECURITY_SERVICE}
        done
    fi
}

# Show help
_show_help(){
    cat << EOF
Usage: sh ${SCRIPT_NAME} [option]

Options:
    --common                    Install common services.

    --stack [stack]             Choose stack will be installed.
                                Support: $(echo ${List_STACK[*]} | sed 's/ /|/g')

    --backup [backup-service]   Choose backup service will be installed.
                                Support: $(echo ${List_BACKUP[*]} | sed 's/ /|/g')

    --cache [cache-service]     Choose cache service will be installed. Can use multiple --cache options.
                                Support: $(echo ${List_CACHE[*]} | sed 's/ /|/g')

    --extra [extra-service]     Install extra services. Can use multiple --extra options.
                                Support: $(echo ${List_EXTRA[*]} | sed 's/ /|/g')

    --ftp [ftp-server]          Choose ftp server will be installed.
                                Support: $(echo ${List_FTP[*]} | sed 's/ /|/g')

    --mariadb [mariadb-version] Choose MariaDB version will be installed.
                                Support: $(echo ${List_MARIADB[*]} | sed 's/ /|/g')

    --nodejs [nodejs-version]   Choose Node.js version will be installed.
                                Support: $(echo ${List_NODEJS[*]} | sed 's/ /|/g')

    --php [php-version]         Choose php version will be installed. Can use multiple --php options.
                                Support: $(echo ${List_PHP[*]} | sed 's/ /|/g')

    --security [security]       Install security services. Can use multiple --security options.
                                Support: $(echo ${List_SECURITY[*]} | sed 's/ /|/g')

    --web [web-server]          Choose web server will be installed.
                                Support: $(echo ${List_WEB[*]} | sed 's/ /|/g')

    --skip [action-name]        Skip action when run. Can use multiple --skip options.
                                Support: $(echo ${List_SKIP_ACTION[*]} | sed 's/ /|/g')

    --exclude [service-name]    Exclude service will be installed. Can use multiple --exclude options.
                                If service has multiple versions, must use service name before version.
                                Example: php7.4, nodejs8.x, mariadb10.4

    --update                    Update build.sh script to latest version.
    --help                      Show help.
    --version                   Show version.

Use "sh ${SCRIPT_NAME} [option] --help" for more information about a option.

Example:
    sh ${SCRIPT_NAME} --common
    sh ${SCRIPT_NAME} --stack lemp
    sh ${SCRIPT_NAME} --php 7.3 --web nginx --mariadb 10.4 --ftp proftpd --extra phpmyadmin --security csf
    sh ${SCRIPT_NAME} --common --exclude php7.4 --php 7.3 --exclude csf --security clamav
    
    sh ${SCRIPT_NAME} --help
    sh ${SCRIPT_NAME} --common --help
EOF
}

# Main
_create_dir
_start_install
_check_os

# Get options
if [ $# -eq 0 ]
then
    _show_log -d -r " [FAIL]" -w " The script requires at least one argument. Exit!"
    _exit_build 1
fi

while (( "$#" ))
do
    case $1 in
        --common)
            if [ "$2" == "--help" ]
            then
                echo "Usage: sh ${SCRIPT_NAME} --common"
                echo "This option will be install following services:"
                echo "---"
                echo "FTP server     : ${DEFAULT_FTP_SERVER}"
                echo "PHP version    : ${DEFAULT_PHP_VERSION}"
                echo "Nodejs version : ${DEFAULT_NODEJS}"
                echo "MariaDB version: ${DEFAULT_SQL_SERVER}"
                echo "Web server     : ${DEFAULT_WEB_SERVER}"
                echo "Extra service  : ${List_EXTRA[*]:1}"
                echo "Security       : ${List_SECURITY[*]:1}"
                echo ""
                echo "Example:"
                echo "    sh ${SCRIPT_NAME} --common"
                echo "    sh ${SCRIPT_NAME} --common --php 7.3 --web openlitespeed --exclude nodejs12.x"
                _exit_build 0
            else
                INSTALL_COMMON=1
                shift
            fi
            ;;
        --stack)
            if [ "$2" == "--help" ]
            then
                echo "Usage: sh ${SCRIPT_NAME} --stack [stack]"
                echo "[stack] = `echo ${List_STACK[*]} | sed 's/ /|/g'`"
                echo ""
                echo "This option will be install following services:"
                for i_STACK in ${List_STACK[*]}
                do
                    echo "---"
                    echo "[stack] = ${i_STACK}"
                    echo "FTP server     : ${DEFAULT_FTP_SERVER}"
                    echo "PHP version    : ${DEFAULT_PHP_VERSION}"
                    echo "Nodejs version : ${DEFAULT_NODEJS}"
                    echo "MariaDB version: ${DEFAULT_SQL_SERVER}"
                    if [ "${i_STACK}" == "lamp" ]
                    then
                        OPTION_WEB_SERVER="httpd"
                    elif [ "${i_STACK}" == "lemp" ]
                    then
                        OPTION_WEB_SERVER="nginx"
                    elif [ "${i_STACK}" == "lomp" ]
                    then
                        OPTION_WEB_SERVER="openlitespeed"
                    fi
                    echo "Web server     : ${OPTION_WEB_SERVER}"
                    echo "Extra service  : phpmyadmin"
                    echo "Security       : csf"
                done
                echo ""
                echo "Example:"
                echo "    sh ${SCRIPT_NAME} --stack lemp"
                echo "    sh ${SCRIPT_NAME} --stack lamp --php 7.3"
                _exit_build 0
            else
                _get_option single $1 GET_STACK $2
                _check_value_in_list "Stack" "${GET_STACK}" "${List_STACK[*]}"
                shift 2
            fi
            ;;
        --backup)
            if [ "$2" == "--help" ]
            then
                echo "Usage: sh ${SCRIPT_NAME} --backup [backup-service]"
                echo "[backup-service] = `echo ${List_BACKUP[*]} | sed 's/ /|/g'`"
                echo ""
                echo "This option will be install following services:"
                for i_BACKUP in ${List_BACKUP[*]}
                do
                    echo "---"
                    echo "[backup-service] = ${i_BACKUP}"
                    if [ "${i_BACKUP}" == "all" ]
                    then
                        i_BACKUP="${List_BACKUP[*]:1}"
                    fi
                    echo "Backup: ${i_BACKUP}"
                done
                echo ""
                echo "Example:"
                echo "    sh ${SCRIPT_NAME} --backup all"
                echo "    sh ${SCRIPT_NAME} --backup rclone --backup restic"
                _exit_build 0
            else
                if [ "${GET_BACKUP_SERVICE}" != "all" ]
                then
                    if [ "$2" == "all" ]
                    then
                        GET_BACKUP_SERVICE="all"
                    else
                        _get_option multi $1 GET_BACKUP_SERVICE $2
                        _check_value_in_list "Backup service" "${GET_BACKUP_SERVICE}" "${List_BACKUP[*]}"
                        GET_BACKUP_SERVICE=($(echo "${GET_BACKUP_SERVICE[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
                    fi
                fi
                shift 2
            fi
            ;;
        --cache)
            if [ "$2" == "--help" ]
            then
                echo "Usage: sh ${SCRIPT_NAME} --cache [cache-service]"
                echo "[cache-service] = `echo ${List_CACHE[*]} | sed 's/ /|/g'`"
                echo ""
                echo "This option will be install following services:"
                for i_CACHE in ${List_CACHE[*]}
                do
                    echo "---"
                    echo "[cache-service] = ${i_CACHE}"
                    if [ "${i_CACHE}" == "all" ]
                    then
                        i_CACHE="${List_CACHE[*]:1}"
                    fi
                    echo "Cache: ${i_CACHE}"
                done
                echo ""
                echo "Example:"
                echo "    sh ${SCRIPT_NAME} --cache all"
                echo "    sh ${SCRIPT_NAME} --cache memcached --cache redis"
                echo "    sh ${SCRIPT_NAME} --cache memcached --web nginx --php 7.2"
                _exit_build 0
            else
                if [ "${GET_CACHE_SERVICE}" != "all" ]
                then
                    if [ "$2" == "all" ]
                    then
                        GET_CACHE_SERVICE="all"
                    else
                        _get_option multi $1 GET_CACHE_SERVICE $2
                        _check_value_in_list "Backup service" "${GET_CACHE_SERVICE}" "${List_CACHE[*]}"
                        GET_CACHE_SERVICE=($(echo "${GET_CACHE_SERVICE[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
                    fi
                fi
                shift 2
            fi
            ;;
        --extra)
            if [ "$2" == "--help" ]
            then
                echo "Usage: sh ${SCRIPT_NAME} --extra [extra-service]"
                echo "[extra-service] = `echo ${List_EXTRA[*]} | sed 's/ /|/g'`"
                echo ""
                echo "This option will be install following services:"
                for i_EXTRA in ${List_EXTRA[*]}
                do
                    echo "---"
                    echo "[extra-service] = ${i_EXTRA}"
                    if [ "${i_EXTRA}" == "all" ]
                    then
                        i_EXTRA="${List_EXTRA[*]:1}"
                    fi
                    echo "Extra service: ${i_EXTRA}"
                done
                echo ""
                echo "Example:"
                echo "    sh ${SCRIPT_NAME} --extra all"
                echo "    sh ${SCRIPT_NAME} --extra phpmyadmin --extra vnstat"
                _exit_build 0
            else
                if [ "${EXTRA_SERVICE}" != "all" ]
                then
                    if [ "$2" == "all" ]
                    then
                        EXTRA_SERVICE="all"
                    else
                        _get_option multi $1 EXTRA_SERVICE $2
                        _check_value_in_list "Extra service" "${EXTRA_SERVICE}" "${List_EXTRA[*]}"
                        EXTRA_SERVICE=($(echo "${EXTRA_SERVICE[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
                    fi
                fi
                shift 2
            fi
            ;;
        --ftp)
            if [ "$2" == "--help" ]
            then
                echo "Usage: sh ${SCRIPT_NAME} --ftp [ftp-server]"
                echo "[ftp-server] = `echo ${List_FTP[*]} | sed 's/ /|/g'`"
                echo ""
                echo "This option will be install following services:"
                for i_FTP in ${List_FTP[*]}
                do
                    echo "---"
                    echo "[ftp-server] = ${i_FTP}"
                    echo "FTP server: ${i_FTP}"
                done
                echo ""
                echo "Example:"
                echo "    sh ${SCRIPT_NAME} --ftp pure-ftpd"
                _exit_build 0
            else
                _get_option single $1 GET_FTP_SERVER $2
                _check_value_in_list "FTP server" "${GET_FTP_SERVER}" "${List_FTP[*]}"
                shift 2
            fi
            ;;
        --mariadb)
            if [ "$2" == "--help" ]
            then
                echo "Usage: sh ${SCRIPT_NAME} --mariadb [mariadb-version]"
                echo "[mariadb-version] = `echo ${List_MARIADB[*]} | sed 's/ /|/g'`"
                echo ""
                echo "This option will be install following services:"
                for i_MARIADB in ${List_MARIADB[*]}
                do
                    echo "---"
                    echo "[mariadb-version] = ${i_MARIADB}"
                    echo "MariaDB version: ${i_MARIADB}"
                done
                echo ""
                echo "Example:"
                echo "    sh ${SCRIPT_NAME} --mariadb 10.4"
                _exit_build 0
            else
                _get_option single $1 GET_MARIADB $2
                _check_value_in_list "MariaDB version" "${GET_MARIADB}" "${List_MARIADB[*]}"
                shift 2
            fi
            ;;
        --nodejs)
            if [ "$2" == "--help" ]
            then
                echo "Usage: sh ${SCRIPT_NAME} --nodejs [nodejs-version]"
                echo "[nodejs-version] = `echo ${List_NODEJS[*]} | sed 's/ /|/g'`"
                echo ""
                echo "This option will be install following services:"
                for i_NODEJS in ${List_NODEJS[*]}
                do
                    echo "---"
                    echo "[nodejs-version] = ${i_NODEJS}"
                    echo "Nodejs version: ${i_NODEJS}"
                done
                echo ""
                echo "Example:"
                echo "    sh ${SCRIPT_NAME} --nodejs 14.x"
                _exit_build 0
            else
                _check_value_in_list "Nodejs version" "$2" "${List_NODEJS[*]}"
                _get_option single $1 GET_NODEJS $2
                shift 2
            fi
            ;;
        --php)
            if [ "$2" == "--help" ]
            then
                echo "Usage: sh ${SCRIPT_NAME} --php [php-version]"
                echo "[php-version] = `echo ${List_PHP[*]} | sed 's/ /|/g'`"
                echo ""
                echo "This option will be install following services:"
                for i_PHP in ${List_PHP[*]}
                do
                    echo "---"
                    echo "[php-version] = ${i_PHP}"
                    if [ "${i_PHP}" == "all" ]
                    then
                        i_PHP="${List_PHP[*]:1}"
                    fi
                    echo "PHP version: ${i_PHP}"
                done
                echo ""
                echo "Example:"
                echo "    sh ${SCRIPT_NAME} --php all"
                echo "    sh ${SCRIPT_NAME} --php 7.0 --php 7.3"
                echo "    sh ${SCRIPT_NAME} --php all --exclude php7.2"
                _exit_build 0
            else
                if [ "${GET_PHP_VERSION}" != "all" ]
                then
                    if [ "$2" == "all" ]
                    then
                        GET_PHP_VERSION="all"
                    else
                        _get_option multi $1 GET_PHP_VERSION $2
                        _check_value_in_list "PHP version" "${GET_PHP_VERSION}" "${List_PHP[*]}"
                        GET_PHP_VERSION=($(echo "${GET_PHP_VERSION[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
                    fi
                fi
                shift 2
            fi
            ;;
        --security)
            if [ "$2" == "--help" ]
            then
                echo "Usage: sh ${SCRIPT_NAME} --security [security]"
                echo "[security] = `echo ${List_SECURITY[*]} | sed 's/ /|/g'`"
                echo ""
                echo "This option will be install following services:"
                for i_SECURITY in ${List_SECURITY[*]}
                do
                    echo "---"
                    echo "[security] = ${i_SECURITY}"
                    if [ "${i_SECURITY}" == "all" ]
                    then
                        i_SECURITY="${List_SECURITY[*]:1}"
                    fi
                    echo "Security: ${i_SECURITY}"
                done
                echo ""
                echo "Example:"
                echo "    sh ${SCRIPT_NAME} --security all"
                echo "    sh ${SCRIPT_NAME} --security acme_sh --security clamav"
                echo "    sh ${SCRIPT_NAME} --security all --exclude csf"
                _exit_build 0
            else
                if [ "${SECURITY_SERVICE}" != "all" ]
                then
                    if [ "$2" == "all" ]
                    then
                        SECURITY_SERVICE="all"
                    else
                        _get_option multi $1 SECURITY_SERVICE $2
                        _check_value_in_list "Security service" "${SECURITY_SERVICE}" "${List_SECURITY[*]}"
                        SECURITY_SERVICE=($(echo "${SECURITY_SERVICE[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
                    fi
                fi
                shift 2
            fi
            ;;
        --update)
            rm -f $0
            curl -so $0 ${GITHUB_LINK}/build.sh
            chmod 755 $0
            _exit_build 0
            ;;
        --web)
            if [ "$2" == "--help" ]
            then
                echo "Usage: sh ${SCRIPT_NAME} --web [web-server]"
                echo "[web-server] = `echo ${List_WEB[*]} | sed 's/ /|/g'`"
                echo ""
                echo "This option will be install following services:"
                for i_WEB in ${List_WEB[*]}
                do
                    echo "---"
                    echo "[web-server] = ${i_WEB}"
                    echo "Web server: ${i_WEB}"
                done
                echo ""
                echo "Example:"
                echo "    sh ${SCRIPT_NAME} --web nginx"
                _exit_build 0
            else
                _get_option single $1 GET_WEB_SERVER $2
                _check_value_in_list "Web server" "${GET_WEB_SERVER}" "${List_WEB[*]}"
                shift 2
            fi
            ;;
        --exclude)
            if [ "$2" == "--help" ]
            then
                echo "Usage: sh ${SCRIPT_NAME} --exclude [service-name]"
                echo "Exclude service will be installed."
                echo ""
                echo "If service has multiple versions, must use service name before version."
                echo "Example: php7.4, nodejs8.x, mariadb10.4"
                echo ""
                echo "Example:"
                echo "    sh ${SCRIPT_NAME} --security all --exclude csf"
                echo "    sh ${SCRIPT_NAME} --common --exclude nodejs12.x"
                _exit_build 0
            else
                _get_option multi  $1 EXCLUDE_SERVICE $2
                shift 2
            fi
            ;;
        --skip)
            if [ "$2" == "--help" ]
            then
                echo "Usage: sh ${SCRIPT_NAME} --skip [action-name]"
                echo "[action-name] = `echo ${List_SKIP_ACTION[*]} | sed 's/ /|/g'`"
                echo ""
                echo "This option will be SKIP following actions:"
                for i_SKIP in ${List_SKIP_ACTION[*]}
                do
                    echo "---"
                    echo "[action-name] = ${i_SKIP}"
                    if [ "${i_SKIP}" == "all" ]
                    then
                        i_SKIP="${List_SKIP_ACTION[*]:1}"
                    fi
                    echo "Skip action: ${i_SKIP}"
                done
                echo ""
                echo "Example:"
                echo "    sh ${SCRIPT_NAME} --common --skip all"
                echo "    sh ${SCRIPT_NAME} --stack lemp --skip no-update"
                echo "    sh ${SCRIPT_NAME} --web nginx --skip no-start"
                _exit_build 0
            else
                if [ "${SKIP_ACTION}" != "all" ]
                then
                    if [ "$2" == "all" ]
                    then
                        SKIP_ACTION="all"
                    else
                        _check_value_in_list "Skip action" "$2" "${List_SKIP_ACTION[*]}"
                        _get_option multi $1 SKIP_ACTION $2
                        SKIP_ACTION=($(echo "${SKIP_ACTION[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
                    fi
                fi
                shift 2
            fi
            ;;        
        --help)
            _show_help
            _exit_build 0
            ;;
        --version)
            head -n 5 ${SCRIPT_NAME} | grep "^# Version:" | awk '{print $3}'
            _exit_build 0
            ;;
        *)
            _show_log -d -r " [FAIL]" -w " Do not support option ${RED}$1${REMOVE}. Exit!"
            _exit_build 1
            ;;
    esac
done

_check_user_root
_check_network
_check_control_panel
_check_info
_update_sys
_pre_install
_main_install
_end_install
_download_mce
