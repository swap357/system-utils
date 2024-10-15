#!/bin/bash

# Check if script is run as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Function to get CPU information
get_cpu_info() {
    echo "CPU Information:"
    lscpu | grep -E "^CPU\(s\):|^Thread\(s\) per core:|^Core\(s\) per socket:|^Socket\(s\):|^Model name:" | sed 's/^/  /'
}

# Function to get isolated cores
get_isolated_cores() {
    echo "Isolated Cores:"
    isolated=$(cat /sys/devices/system/cpu/isolated)
    if [ -z "$isolated" ]; then
        echo "  No cores are isolated"
    else
        echo "  $isolated"
    fi
}

# Function to analyze interrupt distribution
analyze_interrupts() {
    echo "Interrupt Analysis:"
    local isolated_cores=$(cat /sys/devices/system/cpu/isolated)
    local total_interrupts=0
    local isolated_interrupts=0
    local busiest_irq=0
    local busiest_irq_count=0
    local busiest_irq_name=""
    
    while read line; do
        if [[ $line =~ ^[[:space:]]*([0-9]+): ]]; then
            irq="${BASH_REMATCH[1]}"
            irq_name=$(echo "$line" | awk '{print $NF}')
            irq_count=0
            for i in {1..28}; do
                count=$(echo "$line" | awk -v col=$((i+1)) '{print $col}')
                if [[ $count =~ ^[0-9]+$ ]]; then
                    irq_count=$((irq_count + count))
                    if [[ $isolated_cores =~ $((i-1)) ]]; then
                        isolated_interrupts=$((isolated_interrupts + count))
                    fi
                fi
            done
            total_interrupts=$((total_interrupts + irq_count))
            if [ $irq_count -gt $busiest_irq_count ]; then
                busiest_irq=$irq
                busiest_irq_count=$irq_count
                busiest_irq_name=$irq_name
            fi
        fi
    done < /proc/interrupts
    
    echo "  Total Interrupts: $total_interrupts"
    echo "  Interrupts on Isolated Cores: $isolated_interrupts"
    echo "  Percentage on Isolated Cores: $(awk "BEGIN {printf \"%.2f%%\", $isolated_interrupts / $total_interrupts * 100}")"
    echo "  Busiest IRQ: $busiest_irq ($busiest_irq_name) with $busiest_irq_count interrupts"
}

# Function to get CPU frequency information
get_cpu_freq_info() {
    echo "CPU Frequency Information:"
    cpupower frequency-info | grep -E "hardware limits:|current CPU frequency:" | sed 's/^/  /'
}

# Function to get CPU governor information
get_cpu_governor_info() {
    echo "CPU Governor Information:"
    cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort | uniq -c | awk '{print "  " $2 ": " $1 " CPU(s)"}'
}

# Function to run turbostat and parse output
run_turbostat() {
    echo "Turbostat Summary (5-second sample):"
    turbostat --quiet --show "Core,CPU,Busy%,Bzy_MHz,IRQ,PkgWatt,CoreTmp" -i 5 1 2>&1 | \
    awk 'NR>1 {core[$1] = $1; cpu[$2] = $2; busy[$1] += $3; freq[$1] += $4; irq[$1] += $5; temp[$1] = $7; count[$1]++} 
    END {
        if (length(busy) > 0) {
            printf "  Avg Busy%%: %.2f%%\n", sum(busy)/length(busy);
            printf "  Avg Freq: %.2f MHz\n", sum(freq)/length(freq);
            printf "  Total IRQs: %d\n", sum(irq);
            printf "  Avg Temp: %.2f°C\n", sum(temp)/length(temp);
            printf "  Busiest Core: %s (%.2f%%)\n", core[maxidx(busy)], busy[maxidx(busy)]/count[maxidx(busy)];
            printf "  Coolest Core: %s (%.2f°C)\n", core[minidx(temp)], temp[minidx(temp)];
            printf "  Hottest Core: %s (%.2f°C)\n", core[maxidx(temp)], temp[maxidx(temp)];
        } else {
            print "  No data available from turbostat"
        }
    }
    function sum(arr) {
        s = 0;
        for (i in arr) s += arr[i];
        return s;
    }
    function maxidx(arr) {
        max = -1;
        for (i in arr) if (arr[i]/count[i] > max) { max = arr[i]/count[i]; idx = i }
        return idx;
    }
    function minidx(arr) {
        min = 1e10;
        for (i in arr) if (arr[i] < min) { min = arr[i]; idx = i }
        return idx;
    }'
}

# Main execution
echo "Advanced CPU State Check Summary"
echo "================================"
echo

get_cpu_info
echo

get_isolated_cores
echo

analyze_interrupts
echo

get_cpu_freq_info
echo

get_cpu_governor_info
echo

run_turbostat
echo

echo "Interpretation Guide:"
echo "---------------------"
echo "1. Isolated Cores: These cores are reserved and not used for general tasks."
echo "2. Interrupt Analysis:"
echo "   - High percentage of interrupts on isolated cores may indicate ineffective isolation."
echo "   - Busiest IRQ helps identify which device or process is generating the most interrupts."
echo "3. CPU Frequency: Indicates the current operating frequency of the CPUs."
echo "4. CPU Governor: The power management strategy in use (e.g., 'schedutil' for scheduler-driven)."
echo "5. Turbostat Summary: Provides a snapshot of CPU performance and thermal state."
echo "   - High 'Busy%' on isolated cores may indicate isolation is not fully effective."
echo "   - 'Avg Freq' below maximum might suggest power saving or thermal throttling."
echo "   - High 'Avg Temp' could indicate cooling issues."
echo

echo "Useful Commands for Further Investigation:"
echo "----------------------------------------"
echo "1. View real-time CPU usage: top"
echo "2. Detailed interrupt info: cat /proc/interrupts"
echo "3. CPU frequency details: watch -n1 \"cat /proc/cpuinfo | grep MHz\""
echo "4. Current CPU governor: cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
echo "5. Full turbostat output: turbostat --show Core,CPU,Busy%,Bzy_MHz,IRQ,PkgWatt,CoreTmp"
echo "6. Process-core affinity: ps -eo pid,comm,psr"

echo "Check complete."