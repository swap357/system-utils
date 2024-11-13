#!/bin/bash

while true; do
    # CPU utilization from /proc/stat
    read cpu user nice system idle iowait irq softirq steal guest guest_nice <<< "$(grep '^cpu ' /proc/stat)"
    
    # Calculate total and individual CPU states
    total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    idle=$((idle + iowait))
    
    # Calculate percentages for each state
    [ -n "$ptotal" ] && {
        period=$((total - ptotal))
        cpu_usage=$(( 100 * ( (total-idle) - (ptotal-pidle) ) / period ))
        user_pct=$(( 100 * (user - puser) / period ))
        system_pct=$(( 100 * (system - psystem) / period ))
        iowait_pct=$(( 100 * (iowait - piowait) / period ))
        irq_total_pct=$(( 100 * ((irq + softirq) - (pirq + psoftirq)) / period ))
    }

    # Store previous values
    ptotal=$total
    pidle=$idle
    puser=$user
    psystem=$system
    piowait=$iowait
    pirq=$irq
    psoftirq=$softirq

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
    echo "CPU Usage Breakdown:"
    echo "├─ Total: ${cpu_usage:=0}%"
    echo "├─ User: ${user_pct:=0}%"
    echo "├─ System: ${system_pct:=0}%"
    echo "├─ I/O Wait: ${iowait_pct:=0}%"
    echo "└─ IRQ/SoftIRQ: ${irq_total_pct:=0}%"
    echo
    echo "Memory Used: $(awk "BEGIN {printf \"%.2f\", ${mem_used}/1048576}")GB / $(awk "BEGIN {printf \"%.2f\", ${mem_total}/1048576}")GB"
    [ "$gpu_util" != "N/A" ] && echo "GPU Usage: ${gpu_util}%"

    sleep 1
done