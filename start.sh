#!/bin/bash

#****************************************************
#2018-02-11 V1.0 --haibo.yuan
#基于curl限速功能开发工具输出指定带宽压力，具体功能包括
#    1. 输出带宽大小可配置
#    2. 可以同时对多个服务器按照指定比例做压力测试
#    3. 运行时间可配置，请求目标URL可以根据资源配置
#   
#2018-03-26 V1.1 --haibo.yuan
#增加磁盘IO性能测试方式，具体
#    1. 增加磁盘IO性能测试接口，如./start.sh start -t disk
#    2. 增加停止接口可以随时停止运行中的压力脚本，如./start.sh stop
#
#2019-06-06 V1.2 --haibo.yuan
#模拟页面系统小文件带宽测试
#    1. 带宽测试中支持https协议
#    2. 最大并发量在config里可配
#    3. 小文件类URL条数很多可以单独放在config外文件test_url_list.txt
#****************************************************

MAIN_PROGRAMM="loadAgent.sh"

action=start    #缺省启动脚本
testType=band   #缺省做带宽测试

usage() {
    echo "Usage: ./$(basename $0) [start|stop] [-t|-type band|disk]"
    exit
}

while [ -n "$1" ];do
    case "$1" in
        start|stop)
            action=$1
            shift;;
        -t|-type)
            testType=$2
            shift 2;;
        *)
            echo "$1 is invalid option"
            usage;;
    esac
done

#main
if [ "$action" == "stop" ];then
    ps -ef|grep ${MAIN_PROGRAMM}  |grep -v grep  |awk '{print $2}' |xargs kill -9 >/dev/null 2>&1
    ps -ef|grep curl  |grep -v grep  |awk '{print $2}' |xargs kill -9 >/dev/null 2>&1
    sed -i 's/\*\/1 \* \* \* \* root \/usr\/lib64\/sa\/sa1 1 1/\*\/10 \* \* \* \* root \/usr\/lib64\/sa\/sa1 1 1/g'  /etc/cron.d/sysstat
    exit
else
    #进入文件所在路径
    cd $(dirname "$0")
    
    #检查主程序存在以及权限
    if [ ! -f "./${MAIN_PROGRAMM}" ];then
        echo "${MAIN_PROGRAMM} does not exist in $(pwd)"
        exit 1
    elif [ ! -x "./${MAIN_PROGRAMM}" ];then
        chmod 755 ./${MAIN_PROGRAMM}
    fi
    
    #清空log
    if [ -f "./nohup.out" ];then
        echo -n "" > ./nohup.out
    fi
    
    #删除原来可能的未退出进程并启动
    ps -ef|grep ${MAIN_PROGRAMM}  |grep -v grep  |awk '{print $2}' |xargs kill -9 >/dev/null 2>&1
    ps -ef|grep curl  |grep -v grep  |awk '{print $2}' |xargs kill -9 >/dev/null 2>&1
    sleep 1
    nohup ./${MAIN_PROGRAMM} ${testType} &
fi
