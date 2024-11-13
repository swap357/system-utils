#!/bin/bash

while true; do
    # CPU utilization from /proc/stat
    read cpu user nice system idle iowait irq softirq steal guest guest_nice <<< "$(grep '^cpu ' /proc/stat)"
    total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    idle=$((idle + iowait))
    cpu_usage=$(( 100 * ( (total-idle) - (ptotal-pidle) ) / (total-ptotal) ))
    ptotal=$total
    pidle=$idle

    # Memory info directly from /proc/meminfo
    mem_total=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    mem_available=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}')
    mem_used=$((mem_total - mem_available))

    # GPU utilization if nvidia-smi exists
    if command -v nvidia-smi >/dev/null 2>&1; then
        gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo "N/A")
    else
        gpu_util="N/A"
    fi

    clear
    echo "CPU Usage: ${cpu_usage:=0}%"
    echo "Memory Used: $((mem_used/1024))M / $((mem_total/1024))M"
    echo "Memory Available: $((mem_available/1024))M"
    [ "$gpu_util" != "N/A" ] && echo "GPU Usage: ${gpu_util}%"

    sleep 1
done