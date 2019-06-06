#!/bin/bash

#基本运行参数
LAUNCH_REQUEST_NUM_PERSECOND=1000    #并发启动时每秒启动总数量
PRO_CHECK_PER_SECOND=100  #持续加压时进程每秒检查次数
DELAY_TIME=120  #测试时间到了后没完成请求等待时间，超过这个时间通过杀进程退出
CORRECTION_RATIO=95  #限速校正到设置的95%，请求前几秒限速没有完全生效，整体带宽比设置略高
CONCURRENT_NUM_DISK=100 # 磁盘压力测试并发请求数
DISK_RESULT_FILE="diskIO.txt"   #磁盘压力测试结果文件

#配置以及基本环境检查
precheck() {
    #配置文件是否存在
    if [ -f ./config ];then
        . ./config  
    else
        echo "File config does not exist in $(pwd)"
        exit 1
    fi

    #并发请求数设置
    if [ ! -n ${CONCURRENT_NUM_BAND} ];then
        CONCURRENT_NUM_BAND=1000
    elif [ ${CONCURRENT_NUM_BAND} -gt 10000 ];then
        CONCURRENT_NUM_BAND=10000   #最大并发数10000
    fi

    #输出带宽检查
    if [ ! -n ${Output_Bandwidth} ];then
        Output_Bandwidth=500
    elif [ ${Output_Bandwidth} -gt 8000 ];then
        Output_Bandwidth=8000   #最大带宽不超过8G
    fi

    #运行时长检查
    if [ ! -n ${Run_Time} ];then
        Run_Time=600    #缺省10分钟
    elif [ ${Run_Time} -gt 43200 ];then
        Run_Time=43200  #最长不超过12小时
    fi
    
    #测试URL Key是否存在
    if [ ! -n ${Test_Url_Key} ];then
        echo "Test_Url_Key does not exist in config file"
        exit 1
    fi

    #访问URL总条数是否配置
    if [ ! -n ${Test_Url_Number} ];then
        echo "Test_Url_Number does not exist in config file"
        exit 1
    elif [ ${Test_Url_Number} -lt 100 ];then
        Test_Url_Number=100 #测试总数最小设置100
    fi

    #检查curl程序是否存在
    if [ ! -x "$(which curl)" ];then
        echo "Curl does not exist or not executable"
        exit 1
    fi
}

#启动带宽压力测试并持续按比例输出压力请求 
run_band() {
    #根据基本配置计算每个请求限制带宽
    limitRate=$((Output_Bandwidth*1024*1024*${CORRECTION_RATIO}/8/CONCURRENT_NUM_BAND/100))
    echo "Agent will push ${Output_Bandwidth}Mbps to ${Vip_List_Bandwidth_Ratio[@]} servers, loop time is ${Run_Time} seconds, limit Rate is ${limitRate}bps"
    #根据url list文件预生成curl请求格式
    Curl_Request_Url_List=()
    i=0
    for request_url in ${Test_Url_List[@]};do
        schema=$(echo ${request_url} |awk -F"://" '{print $1}')
        domain=$(echo ${request_url} |awk -F"://" '{print $2}' |awk -F"/" '{print $1}')
        if [ ! -n "${schema}" -o ! -n "${domain}" ];then
            echo "no schema or domain for url ${request_url}"
            exit
        fi
        if [ ${schema} == "https" ];then
            port=443
        else
            port=80
        fi 
        Curl_Request_Url_List[${i}]="${request_url}  --limit-rate ${limitRate} --resolve ${domain}:${port}"
        i=$((i+1))
    done
    for vip_ratio in ${Vip_List_Bandwidth_Ratio[@]};do
        vip=$(echo ${vip_ratio} |cut -f1 -d:)
        ratio=$(echo ${vip_ratio} |cut -f2 -d:)
        echo "Push ${ratio}% of ${CONCURRENT_NUM_BAND} processes to server ${vip}"
        concurrent=$((CONCURRENT_NUM_BAND*ratio/100))
        urlListNum=${#Test_Url_List[@]}
        for((i=0,j=0; i<concurrent; i++,j++));do
            if [ $j -ge $urlListNum ];then
                j=$((j%urlListNum))
            fi
            #echo "i=$i, j=$j, url is ${Test_Url_List[j]}"
            curl -so /dev/null ${Curl_Request_Url_List[j]}:${vip} >/dev/null 2>&1 &
            if [ $i -ne 0 -a $((i%LAUNCH_REQUEST_NUM_PERSECOND)) -eq 0 ];then
                sleep 1
            fi
        done
    done
    
    #监控进程并持续输出压力
    echo "Push load test at [$(date)]"
    start_time=$(date +%s)
    counter=1
    while true;do
        for vip_ratio in ${Vip_List_Bandwidth_Ratio[@]};do
            vip=$(echo ${vip_ratio} |cut -f1 -d:)
            ratio=$(echo ${vip_ratio} |cut -f2 -d:)
            concurrent=$((CONCURRENT_NUM_BAND*ratio/100))
            urlListNum=${#Test_Url_List[@]}
            #补充缺失并发量，起点位置随机
            currentNum=$(ps -ef|grep -v grep |grep curl |grep "${vip}"  |wc -l)
            if [ ${currentNum} -lt ${concurrent} ];then
                newNum=$((concurrent-currentNum))
                url_start=$((RANDOM%urlListNum))
                for((j=0; j<newNum; j++));do
                    url_seq=$(( (url_start+j)%urlListNum ))
                    curl -so /dev/null ${Curl_Request_Url_List[url_seq]}:${vip} >/dev/null 2>&1 &
                done
            fi
            #con_every_url=$((concurrent/urlListNum))    #每个url并发数量
            #con_plus_url=$((concurrent%urlListNum))     #前多少条url并发数加1，并发数不是url条数整数倍情况下
            #for((i=0; i<urlListNum && i<concurrent; i++));do
            #    currentNum=$(ps -ef|grep -v grep |grep curl |grep "${Test_Url_List[i]}\ " |grep "${vip}"  |wc -l)
            #    if [ ${currentNum} -le ${con_every_url} ];then
            #        newNum=$((con_every_url-currentNum))
            #        if [ $i -lt ${con_plus_url} ];then
            #            newNum=$((newNum+1))
            #        fi
            #        #echo "add new $newNum processes"    
            #        for((j=0; j<newNum; j++));do
            #            curl -so /dev/null ${Curl_Request_Url_List[i]}:${vip} >/dev/null 2>&1 &
            #        done    #for newNum
            #    fi
            #done    #for urlListNum
        done    #for vip_ratio
        counter=$((counter%PRO_CHECK_PER_SECOND))  #每连续检查若干次等待1秒
        if [ ${counter} -eq 0 ];then
            sleep 1
        fi
        now_time=$(date +%s)
        if [ $((now_time-start_time)) -gt ${Run_Time} ];then
            sleep ${DELAY_TIME}    #等待一段时间让curl请求自然退出
            #删除未退出请求
            ps -ef|grep -v grep |grep curl |grep "limit-rate" |grep "${limitRate}" |awk '{print $2}' |xargs kill -9 >/dev/null 2>&1
            echo "Finish load test at [$(date)]"
            break 
        fi
        counter=$((counter+1))
    done    #while true
    
}

#启动磁盘压力测试并持续按比例输出压力请求 
run_disk() {
    echo "Agent will push load to ${Vip_List_Bandwidth_Ratio[@]} servers to check the disk IO capability, loop time is ${Run_Time} seconds"
    if_collect_diskIO=false 
    for vip_ratio in ${Vip_List_Bandwidth_Ratio[@]};do
        vip=$(echo ${vip_ratio} |cut -f1 -d:)
        ratio=$(echo ${vip_ratio} |cut -f2 -d:)
        echo "Push ${ratio}% of ${CONCURRENT_NUM_DISK} processes to server ${vip} to check disk IO"
        if [ "$vip" == "127.0.0.1" -o "$vip" == "127.1" ];then
            if_collect_diskIO=true
            echo "Test localhost disk IO, the related info will be collected in ${DISK_RESULT_FILE}"
        fi
        concurrent=$((CONCURRENT_NUM_DISK*ratio/100))
        for((i=0; i<concurrent; i++));do
            curl -so /dev/null "${Test_Url_Key}_${HOSTNAME}_${i}" -x ${vip}:80  >/dev/null 2>&1 &
            if [ $i -ne 0 -a $((i%LAUNCH_REQUEST_NUM_PERSECOND)) -eq 0 ];then
                sleep 1
            fi
        done
    done
    
    #监控进程并持续输出新URL请求
    echo "Push disk IO load test at [$(date)]"
    start_time=$(date +%s)
    if [ "$if_collect_diskIO" == "true" ];then
        mv  /var/log/sa/sa$(date +%d) /var/log/sa/sa$(date +%d)_$(date "+%H_%M_%S")    
        sed -i 's/\*\/10 \* \* \* \* root \/usr\/lib64\/sa\/sa1 1 1/\*\/1 \* \* \* \* root \/usr\/lib64\/sa\/sa1 1 1/g'  /etc/cron.d/sysstat
    fi
    counter=1 
    vip_seq=0
    for vip_ratio in ${Vip_List_Bandwidth_Ratio[@]};do
        vip=$(echo ${vip_ratio} |cut -f1 -d:)
        ratio=$(echo ${vip_ratio} |cut -f2 -d:)
        concurrent[${vip_seq}]=$((CONCURRENT_NUM_DISK*ratio/100))
        cursor[${vip_seq}]=${concurrent[${vip_seq}]}
        vip_seq=$((vip_seq+1))
    done
    while true;do
        vip_seq=0
        for vip_ratio in ${Vip_List_Bandwidth_Ratio[@]};do
            vip=$(echo ${vip_ratio} |cut -f1 -d:)
            currentNum=$(ps -ef|grep -v grep |grep curl |grep "${Test_Url_Key}" |grep "${vip}"  |wc -l)
            if [ ${currentNum} -lt ${concurrent[${vip_seq}]} ];then
                newNum=$(( ${concurrent[${vip_seq}]}-currentNum ))
                #echo "add new $newNum processes"    
                for((j=0; j<newNum; j++));do
                    curl -so /dev/null "${Test_Url_Key}_${HOSTNAME}_$(( ${cursor[${vip_seq}]}+j ))" -x ${vip}:80  >/dev/null 2>&1 &
                done    #for newNum
            fi
            cursor[${vip_seq}]=$(( ${cursor[${vip_seq}]}+newNum ))
            if [ ${cursor[${vip_seq}]} -ge ${Test_Url_Number} ];then
                cursor[${vip_seq}]=$(( ${cursor[${vip_seq}]}%Test_Url_Number ))
            fi
            vip_seq=$((vip_seq+1))
        done    #for vip_ratio
        counter=$((counter%PRO_CHECK_PER_SECOND))  #每连续检查若干次等待1秒
        if [ ${counter} -eq 0 ];then
            sleep 1
        fi
        now_time=$(date +%s)
        if [ $((now_time-start_time)) -gt ${Run_Time} ];then
            if [ "$if_collect_diskIO" == "true" ];then
                sed -i 's/\*\/1 \* \* \* \* root \/usr\/lib64\/sa\/sa1 1 1/\*\/10 \* \* \* \* root \/usr\/lib64\/sa\/sa1 1 1/g'  /etc/cron.d/sysstat
                if [ -f ./${DISK_RESULT_FILE} ];then
                    mv ./${DISK_RESULT_FILE} ./${DISK_RESULT_FILE}_$(date +%s)
                fi
                sar -d -p -f /var/log/sa/sa$(date +%d) > ./${DISK_RESULT_FILE}
                echo "Disk IO test result is in $(pwd)/${DISK_RESULT_FILE}"
            fi
            sleep ${DELAY_TIME}    #等待一段时间让curl请求自然退出
            #删除未退出请求
            ps -ef|grep -v grep |grep curl |awk '{print $2}' |xargs kill -9 >/dev/null 2>&1
            echo "Finish disk IO load test at [$(date)]"
            break 
        fi
        counter=$((counter+1))
    done    #while true
}

#main
precheck
if [ "$1" == "disk" ];then
    run_disk
elif [ "$1" == "band" ];then
    run_band
else
    echo "Test type is disk or band, $1 is invalid"
fi

#iostat -xm 1  2|grep sdl |sed -n '2p' |sed 's/[ ][ ]*/,/g'
#iostat -xm -d sdl sde 1  2|grep sdl |sed -n '2p' |sed 's/[ ][ ]*/,/g'
