#!/bin/bash

set -e

# Log file
LOG_FILE="/var/log/cpu_isolation.log"

# Function to log messages
log_message() {
    echo "$(date): $1" | tee -a "$LOG_FILE"
}

# Check if script is run as root
if [ "$(id -u)" != "0" ]; then
   log_message "This script must be run as root" 
   exit 1
fi

# Function to get the number of P-cores and E-cores
get_core_counts() {
    local cpu_info=$(lscpu)
    local total_cores=$(echo "$cpu_info" | grep "^CPU(s):" | awk '{print $2}')
    local sockets=$(echo "$cpu_info" | grep "^Socket(s):" | awk '{print $2}')
    local cores_per_socket=$(echo "$cpu_info" | grep "^Core(s) per socket:" | awk '{print $4}')
    
    p_cores=$((cores_per_socket * sockets))
    e_cores=$((total_cores - p_cores))
}

# Function to get valid core range for selection
get_valid_range() {
    local core_type=$1
    
    if [ "$core_type" == "P" ]; then
        echo "1-$((p_cores - 1))"
    else
        echo "$p_cores-$((total_cores - 1))"
    fi
}

# Function to validate core selection
validate_core_selection() {
    local selected_cores=$1
    local valid_range=$2
    local core_count=$3
    
    if [[ $selected_cores =~ ^[0-9]+-[0-9]+$ ]]; then
        local start=${selected_cores%-*}
        local end=${selected_cores#*-}
        if [ $start -ge ${valid_range%-*} ] && [ $end -le ${valid_range#*-} ] && [ $((end - start + 1)) -eq $core_count ]; then
            return 0
        fi
    else
        if [ $(echo "$selected_cores" | tr ',' ' ' | wc -w) -ne $core_count ]; then
            return 1
        fi
        
        for core in $(echo "$selected_cores" | tr ',' ' '); do
            if ! [[ $core =~ ^[0-9]+$ ]] || [ $core -lt ${valid_range%-*} ] || [ $core -gt ${valid_range#*-} ]; then
                return 1
            fi
        done
        return 0
    fi
    
    return 1
}

# Function to set IRQ affinity
set_irq_affinity() {
    local non_isolated_cpus=$1
    local affinity_mask=$(printf '%x' $((2**$non_isolated_cpus - 1)))
    
    log_message "Setting IRQ affinity to non-isolated cores..."
    for irq in $(find /proc/irq/* -maxdepth 0 -type d | grep -o '[0-9]*')
    do
        echo $affinity_mask > /proc/irq/$irq/smp_affinity 2>/dev/null || log_message "Failed to set affinity for IRQ $irq"
    done
}

# Function to create irqbalance banscript
create_irqbalance_banscript() {
    local isolated_cpus=$1
    local banscript="/etc/irqbalance-banned-cpus.sh"
    
    log_message "Creating irqbalance banscript..."
    cat << EOF > $banscript
#!/bin/bash
echo $isolated_cpus
EOF
    chmod +x $banscript
    
    # Update irqbalance configuration
    sed -i 's/^OPTIONS=.*/OPTIONS="--banscript='$banscript'"/' /etc/default/irqbalance
}

# Function to set CPU frequency governor
set_cpu_governor() {
    local governor=$1
    log_message "Setting CPU governor to $governor..."
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo $governor > $cpu 2>/dev/null || log_message "Failed to set governor for $cpu"
    done
}

# Main execution
log_message "Starting CPU isolation setup..."

get_core_counts
total_cores=$((p_cores + e_cores))

log_message "System has $p_cores P-cores and $e_cores E-cores."

# Interactive questions
echo "CPU Core Isolation Setup"
echo "------------------------"
echo "Your system has $p_cores P-cores and $e_cores E-cores."

# Select core type
while true; do
    read -p "Do you want to isolate P-cores or E-cores? (P/E): " core_type
    case $core_type in
        [Pp]* ) core_type="P"; max_isolatable=$((p_cores - 1)); break;;
        [Ee]* ) core_type="E"; max_isolatable=$e_cores; break;;
        * ) echo "Please answer P or E.";;
    esac
done

# Provide range and select number of cores to isolate
echo "You can isolate between 1 and $max_isolatable ${core_type}-cores."
while true; do
    read -p "How many cores do you want to isolate? (1-$max_isolatable): " core_count
    if [[ "$core_count" =~ ^[0-9]+$ ]] && [ "$core_count" -ge 1 ] && [ "$core_count" -le "$max_isolatable" ]; then
        break
    fi
    echo "Invalid number. Please enter a number between 1 and $max_isolatable."
done

# Select specific cores
valid_range=$(get_valid_range $core_type)
if [ "$core_count" -eq "$max_isolatable" ]; then
    selected_cores="${valid_range%-*}-${valid_range#*-}"
else
    echo "Valid core range for ${core_type}-cores: $valid_range"
    while true; do
        echo "Enter $core_count core number(s) you want to isolate (comma-separated or range, from $valid_range):"
        read selected_cores
        if validate_core_selection "$selected_cores" "$valid_range" "$core_count"; then
            break
        else
            echo "Invalid selection. Please ensure you select $core_count cores within the valid range."
        fi
    done
fi

# Convert selected cores to CPU numbers
if [ "$core_type" == "P" ]; then
    if [[ $selected_cores =~ ^[0-9]+-[0-9]+$ ]]; then
        start=${selected_cores%-*}
        end=${selected_cores#*-}
        cpu_list=$(seq -s, $start $end | xargs -n1 echo | xargs -I{} echo "{} $(({}+1))" | tr ' ' ',' | tr '\n' ',' | sed 's/,$//')
    else
        cpu_list=$(echo "$selected_cores" | tr ',' ' ' | xargs -n1 echo | xargs -I{} echo "{} $(({}+1))" | tr ' ' ',' | tr '\n' ',' | sed 's/,$//')
    fi
else
    cpu_list=$selected_cores
fi

# Calculate non-isolated CPU count for IRQ affinity
non_isolated_cpus=$((total_cores - core_count))

# Modify GRUB configuration
log_message "Modifying GRUB configuration..."
sed -i.bak "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"isolcpus=$cpu_list nohz_full=$cpu_list rcu_nocbs=$cpu_list /" /etc/default/grub

# Update GRUB
log_message "Updating GRUB..."
update-grub

# Ask user about IRQ management preference
echo "Choose IRQ management method:"
echo "1. Manually set IRQ affinities (static)"
echo "2. Use irqbalance with banned CPUs (dynamic)"
read -p "Enter your choice (1 or 2): " irq_choice

if [ "$irq_choice" == "1" ]; then
    # Create a systemd service to manage isolated cores and IRQ affinity
    log_message "Creating systemd service for CPU isolation and manual IRQ affinity..."
    cat << EOF > /etc/systemd/system/cpu-isolation.service
[Unit]
Description=CPU Isolation and IRQ Affinity Service
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=basic.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for cpu in $(echo $cpu_list | tr ',' ' '); do echo 0 > /sys/devices/system/cpu/cpu\$cpu/online; done; $(declare -f set_irq_affinity); set_irq_affinity $non_isolated_cpus; $(declare -f set_cpu_governor); set_cpu_governor performance'
RemainAfterExit=yes

[Install]
WantedBy=basic.target
EOF

    # Enable the service
    log_message "Enabling CPU isolation and IRQ affinity service..."
    systemctl enable cpu-isolation.service

    # Disable irqbalance
    log_message "Disabling irqbalance..."
    systemctl disable irqbalance
    systemctl stop irqbalance

elif [ "$irq_choice" == "2" ]; then
    # Create irqbalance banscript
    create_irqbalance_banscript "$cpu_list"

    # Create a systemd service to manage isolated cores
    log_message "Creating systemd service for CPU isolation..."
    cat << EOF > /etc/systemd/system/cpu-isolation.service
[Unit]
Description=CPU Isolation Service
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=basic.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for cpu in $(echo $cpu_list | tr ',' ' '); do echo 0 > /sys/devices/system/cpu/cpu\$cpu/online; done; $(declare -f set_cpu_governor); set_cpu_governor performance'
RemainAfterExit=yes

[Install]
WantedBy=basic.target
EOF

    # Enable the service
    log_message "Enabling CPU isolation service..."
    systemctl enable cpu-isolation.service

    # Enable and restart irqbalance
    log_message "Enabling and restarting irqbalance..."
    systemctl enable irqbalance
    systemctl restart irqbalance
else
    log_message "Invalid IRQ management choice. Exiting."
    exit 1
fi

# Set current CPU governor to performance
set_cpu_governor performance

log_message "CPU isolation has been set up for the following CPUs: $cpu_list"
if [ "$irq_choice" == "1" ]; then
    log_message "IRQ affinity has been set to use only non-isolated CPUs (0-$((non_isolated_cpus-1)))"
else
    log_message "IRQ balancing has been configured to avoid isolated CPUs"
fi

echo "CPU isolation has been set up for the following CPUs: $cpu_list"
if [ "$irq_choice" == "1" ]; then
    echo "IRQ affinity has been set to use only non-isolated CPUs (0-$((non_isolated_cpus-1)))"
else
    echo "IRQ balancing has been configured to avoid isolated CPUs"
fi
echo "Please reboot your system for changes to take effect."
echo "Check $LOG_FILE for detailed log information."