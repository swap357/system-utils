#!/bin/bash

# Function to check if script is run as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" 1>&2
        exit 1
    fi
}

# Function to get current governor settings
get_current_settings() {
    echo "Current CPU governor settings:"
    cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
}

# Function to set governor to performance
set_performance_mode() {
    echo "Setting CPU governor to powersave mode..."
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
    do
        echo "powersave" > $cpu
    done
}

# Function to verify new settings
verify_settings() {
    echo "Verifying new CPU governor settings:"
    cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
}

# Main execution
check_root
get_current_settings
set_performance_mode
verify_settings

echo "CPU scaling governor has been set to powersave mode for all cores."
