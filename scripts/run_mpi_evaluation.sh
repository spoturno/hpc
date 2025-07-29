#!/bin/bash

# MPI Chess Search Evaluation Script
# This script evaluates the MPI-based chess search implementation with different process counts

set -e

# Configuration
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
RESULTS_DIR="results"
OUTPUT_FILE="${RESULTS_DIR}/mpi_evaluation_${TIMESTAMP}.csv"
BINARY="./engine-mpi"
EPD_FILE="quiet-labeled.epd"
MAX_PROCESSES=8
DEPTH=6
TIME_LIMIT=10000  # 10 seconds per position

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_color() {
    echo -e "${1}${2}${NC}"
}

# Create results directory if it doesn't exist
mkdir -p "$RESULTS_DIR"

# Check if MPI binary exists
if [ ! -f "$BINARY" ]; then
    echo_color $RED "Error: MPI binary $BINARY not found!"
    echo_color $YELLOW "Please compile with: make engine-mpi"
    exit 1
fi

# Check if EPD file exists
if [ ! -f "$EPD_FILE" ]; then
    echo_color $RED "Error: EPD file $EPD_FILE not found!"
    exit 1
fi

# Check if mpirun is available
if ! command -v mpirun &> /dev/null; then
    echo_color $RED "Error: mpirun not found. Please install MPI."
    exit 1
fi

echo_color $GREEN "Starting MPI Chess Search Evaluation"
echo_color $BLUE "Output file: $OUTPUT_FILE"
echo_color $BLUE "Max processes: $MAX_PROCESSES"
echo_color $BLUE "Depth: $DEPTH"

# Write CSV header
echo "processes,position,move,time_ms,nodes,nps,score" > "$OUTPUT_FILE"

# Function to run a single test
run_test() {
    local processes=$1
    local position_line="$2"
    local position_num=$3
    
    echo_color $YELLOW "Testing with $processes processes - Position $position_num"
    
    # Extract FEN and best move from EPD line
    local fen=$(echo "$position_line" | sed 's/;.*//')
    local best_move=$(echo "$position_line" | grep -o 'bm [^;]*' | cut -d' ' -f2)
    
    # Create UCI commands
    local uci_commands="uci
isready
position fen $fen
go depth $depth
quit"
    
    # Run the MPI engine with timeout
    local start_time=$(date +%s%3N)
    local output
    if output=$(timeout ${TIME_LIMIT}ms mpirun -np "$processes" "$BINARY" <<< "$uci_commands" 2>/dev/null); then
        local end_time=$(date +%s%3N)
        local total_time=$((end_time - start_time))
        
        # Extract search information from output
        local bestmove=$(echo "$output" | grep "bestmove" | tail -1 | awk '{print $2}')
        local info_line=$(echo "$output" | grep "info depth $depth" | tail -1)
        
        if [ -n "$info_line" ]; then
            local time_ms=$(echo "$info_line" | grep -o 'time [0-9]*' | cut -d' ' -f2)
            local nodes=$(echo "$info_line" | grep -o 'nodes [0-9]*' | cut -d' ' -f2)
            local nps=$(echo "$info_line" | grep -o 'nps [0-9]*' | cut -d' ' -f2)
            local score_cp=$(echo "$info_line" | grep -o 'score cp [0-9-]*' | cut -d' ' -f3)
            local score_mate=$(echo "$info_line" | grep -o 'score mate [0-9-]*' | cut -d' ' -f3)
            
            # Use mate score if available, otherwise centipawn score
            local score=${score_mate:-${score_cp:-0}}
            
            # Use extracted values or defaults
            time_ms=${time_ms:-$total_time}
            nodes=${nodes:-0}
            nps=${nps:-0}
            
            echo "$processes,$position_num,$bestmove,$time_ms,$nodes,$nps,$score" >> "$OUTPUT_FILE"
            echo_color $GREEN "  Result: $bestmove (${time_ms}ms, ${nodes} nodes, ${nps} nps)"
        else
            echo_color $RED "  Failed to parse search info"
            echo "$processes,$position_num,timeout,$total_time,0,0,0" >> "$OUTPUT_FILE"
        fi
    else
        echo_color $RED "  Timeout or error occurred"
        echo "$processes,$position_num,timeout,$TIME_LIMIT,0,0,0" >> "$OUTPUT_FILE"
    fi
}

# Read positions from EPD file (limit to first 10 for reasonable test time)
echo_color $BLUE "Reading test positions..."
mapfile -t positions < <(head -10 "$EPD_FILE")
total_positions=${#positions[@]}

echo_color $BLUE "Found $total_positions test positions"

# Test with different numbers of processes
for processes in $(seq 1 $MAX_PROCESSES); do
    echo_color $GREEN "\n=== Testing with $processes processes ==="
    
    position_num=1
    for position_line in "${positions[@]}"; do
        if [ -n "$position_line" ]; then
            run_test "$processes" "$position_line" "$position_num"
            position_num=$((position_num + 1))
        fi
    done
done

echo_color $GREEN "\nMPI evaluation completed!"
echo_color $BLUE "Results saved to: $OUTPUT_FILE"

# Generate summary statistics
echo_color $YELLOW "\nGenerating summary..."
if command -v python3 &> /dev/null; then
    python3 - <<EOF
import pandas as pd
import numpy as np

# Read the results
df = pd.read_csv('$OUTPUT_FILE')

# Filter out timeouts and errors
df_valid = df[df['move'] != 'timeout']

if len(df_valid) > 0:
    print("\n=== Performance Summary ===")
    summary = df_valid.groupby('processes').agg({
        'time_ms': ['mean', 'std'],
        'nodes': ['mean'],
        'nps': ['mean']
    }).round(2)
    
    print(summary)
    
    print("\n=== Speedup Analysis ===")
    baseline = df_valid[df_valid['processes'] == 1]['time_ms'].mean()
    speedup = df_valid.groupby('processes')['time_ms'].mean().apply(lambda x: baseline / x if x > 0 else 0)
    efficiency = speedup / df_valid.groupby('processes').size().index
    
    for processes in sorted(df_valid['processes'].unique()):
        sp = speedup.get(processes, 0)
        eff = efficiency.get(processes, 0) * 100
        print(f"Processes: {processes}, Speedup: {sp:.2f}x, Efficiency: {eff:.1f}%")
else:
    print("No valid results found - all tests timed out or failed")
EOF
else
    echo_color $YELLOW "Python3 not available - skipping summary analysis"
fi

echo_color $GREEN "\nDone!" 