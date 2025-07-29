#!/bin/bash

# Chess Engine Depth and Thread Evaluation Script
# Comprehensive evaluation of Sequential, SharedHashTable, RootSplitting, and MPI algorithms
# Tests depths 1-8 and parallel algorithms with threads/processes 2-8

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  COMPREHENSIVE DEPTH & THREAD EVALUATION"
echo "=========================================="
echo "Testing Date: $(date)"
echo "System: $(uname -s) $(uname -r) $(uname -m)"
echo ""

# Check MPI availability
MPI_AVAILABLE=false
if command -v mpirun &> /dev/null && command -v mpic++ &> /dev/null; then
    MPI_AVAILABLE=true
    echo "✅ MPI detected: $(mpirun --version 2>/dev/null | head -n 1)"
else
    echo "⚠️  MPI not available - MPI tests will be skipped"
fi
echo ""

# Test configurations
declare -a algorithms=("Sequential" "SharedHashTable" "RootSplitting")
declare -a descriptions=("Single-threaded baseline" "Parallel with shared TT" "Parallel with root splitting")
declare -a files=("old-search.cpp" "search-sht.cpp" "search-rs.cpp")

# Add MPI if available
if $MPI_AVAILABLE; then
    algorithms+=("MPI")
    descriptions+=("Distributed parallel with MPI")
    files+=("search-mpi.cpp")
fi

# Test position (starting position)
test_position="rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

# Function to build algorithm
build_algorithm() {
    local name="$1"
    local file="$2"
    
    if [[ "$name" == "MPI" ]]; then
        if $MPI_AVAILABLE; then
            if make clean > /dev/null 2>&1 && make engine-mpi > /dev/null 2>&1; then
                return 0
            else
                return 1
            fi
        else
            return 1
        fi
    else
        ln -sf "$file" search.cpp
        if make clean > /dev/null 2>&1 && make > /dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi
}

# Cross-platform timeout function
run_with_timeout() {
    local timeout_duration=$1
    shift
    local command="$@"
    
    # Use different timeout methods based on available commands
    if command -v gtimeout &> /dev/null; then
        gtimeout "$timeout_duration" $command
    elif command -v timeout &> /dev/null; then
        timeout "$timeout_duration" $command
    else
        # Fallback: run without timeout but with shorter time limit
        $command
    fi
}

# Function to run engine with proper command
run_engine() {
    local name="$1"
    local command="$2"
    local processes="$3"
    
    if [[ "$name" == "MPI" ]]; then
        if $MPI_AVAILABLE; then
            # Create temporary input file for MPI to avoid stdin issues
            local temp_input="/tmp/mpi_input_$$"
            echo -e "$command" > "$temp_input"
            
            # Try multiple MPI approaches
            local mpi_result=""
            
            # First try: standard approach with timeout
            mpi_result=$(run_with_timeout 90s mpirun -np "$processes" --bind-to none ./engine-mpi < "$temp_input" 2>&1)
            
            # If that fails, try without binding
            if [[ -z "$mpi_result" || "$mpi_result" == *"timeout"* ]]; then
                mpi_result=$(run_with_timeout 90s mpirun -np "$processes" ./engine-mpi < "$temp_input" 2>&1)
            fi
            
            # Clean up temp file
            rm -f "$temp_input"
            
            echo "$mpi_result"
        else
            echo "MPI not available"
            return 1
        fi
    else
        echo -e "$command" | ./engine 2>&1
    fi
}

# Function to run a single evaluation
run_evaluation() {
    local algorithm="$1"
    local depth="$2"
    local threads="$3"
    
    if [[ "$algorithm" == "MPI" ]]; then
        # For MPI, threads parameter represents number of processes
        local processes="$threads"
    else
        # For OpenMP algorithms, set thread count
        if [[ "$threads" != "1" ]]; then
            export OMP_NUM_THREADS=$threads
        else
            unset OMP_NUM_THREADS
        fi
    fi
    
    local start_time=$(date +%s%N)
    local result
    if [[ "$algorithm" == "MPI" ]]; then
        result=$(run_engine "$algorithm" "uci\nposition fen $test_position\ngo depth $depth\nquit" "$threads")
    else
        result=$(run_engine "$algorithm" "uci\nposition fen $test_position\ngo depth $depth\nquit")
    fi
    local end_time=$(date +%s%N)
    local wall_time=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
    
    local info_line=$(echo "$result" | grep "info.*depth.*$depth" | tail -n 1)
    local bestmove_line=$(echo "$result" | grep "bestmove" | head -n 1)
    
    if [[ -n "$info_line" ]]; then
        local nodes=$(echo "$info_line" | grep -o 'nodes [0-9]*' | awk '{print $2}')
        local time=$(echo "$info_line" | grep -o 'time [0-9]*' | awk '{print $2}')
        local nps=$(echo "$info_line" | grep -o 'nps [0-9]*' | awk '{print $2}')
        local score=$(echo "$info_line" | grep -o 'score cp [0-9-]*' | awk '{print $3}')
        local best_move=$(echo "$bestmove_line" | awk '{print $2}')
        
        # Use wall time if engine time is 0
        if [[ "$time" == "0" || -z "$time" ]]; then
            time=$wall_time
        fi
        
        echo "$algorithm,$depth,$threads,$nodes,$time,$wall_time,$nps,$score,$best_move"
    else
        echo "$algorithm,$depth,$threads,ERROR,ERROR,ERROR,ERROR,ERROR,ERROR"
    fi
}

# Create results directory
mkdir -p results
timestamp=$(date +"%Y%m%d_%H%M%S")
results_file="results/depth_thread_evaluation_$timestamp.csv"

# Write CSV header
if $MPI_AVAILABLE; then
    echo "Algorithm,Depth,Threads/Processes,Nodes,EngineTime(ms),WallTime(ms),NPS,Score,BestMove" > "$results_file"
    echo "📊 Starting comprehensive evaluation (including MPI)..."
else
    echo "Algorithm,Depth,Threads,Nodes,EngineTime(ms),WallTime(ms),NPS,Score,BestMove" > "$results_file"
    echo "📊 Starting comprehensive evaluation (MPI skipped - not available)..."
fi
echo "Results will be saved to: $results_file"
echo ""

# Sequential Algorithm Evaluation (depths 1-8)
echo "=========================================="
echo -e "${GREEN}SEQUENTIAL ALGORITHM EVALUATION${NC}"
echo "=========================================="
echo "Testing depths 1-8 with single thread..."
echo ""

if build_algorithm "Sequential" "old-search.cpp"; then
    echo -e "${BLUE}Algorithm: Sequential${NC}"
    printf "%-8s %-10s %-12s %-10s %-12s %-10s\n" "Depth" "Nodes" "Time(ms)" "NPS" "Score" "Best Move"
    echo "----------------------------------------------------------------"
    
    for depth in {1..8}; do
        result=$(run_evaluation "Sequential" $depth 1)
        echo "$result" >> "$results_file"
        
        # Parse result for display
        IFS=',' read -r alg d th nodes time wall_time nps score move <<< "$result"
        if [[ "$nodes" != "ERROR" ]]; then
            printf "%-8s %-10s %-12s %-10s %-12s %-10s\n" "$d" "$nodes" "$time" "$nps" "$score" "$move"
        else
            printf "%-8s %-10s %-12s %-10s %-12s %-10s\n" "$d" "ERROR" "ERROR" "ERROR" "ERROR" "ERROR"
        fi
    done
    echo ""
else
    echo -e "${RED}❌ Build failed for Sequential algorithm${NC}"
    echo ""
fi

# SharedHashTable Algorithm Evaluation (depths 1-8, threads 2-8)
echo "=========================================="
echo -e "${GREEN}SHARED HASH TABLE ALGORITHM EVALUATION${NC}"
echo "=========================================="
echo "Testing depths 1-8 with threads 2-8..."
echo ""

if build_algorithm "SharedHashTable" "search-sht.cpp"; then
    echo -e "${BLUE}Algorithm: SharedHashTable${NC}"
    
    for threads in {2..8}; do
        echo ""
        echo -e "${CYAN}--- Testing with $threads threads ---${NC}"
        printf "%-8s %-10s %-12s %-10s %-12s %-10s\n" "Depth" "Nodes" "Time(ms)" "NPS" "Score" "Best Move"
        echo "----------------------------------------------------------------"
        
        for depth in {1..8}; do
            result=$(run_evaluation "SharedHashTable" $depth $threads)
            echo "$result" >> "$results_file"
            
            # Parse result for display
            IFS=',' read -r alg d th nodes time wall_time nps score move <<< "$result"
            if [[ "$nodes" != "ERROR" ]]; then
                printf "%-8s %-10s %-12s %-10s %-12s %-10s\n" "$d" "$nodes" "$time" "$nps" "$score" "$move"
            else
                printf "%-8s %-10s %-12s %-10s %-12s %-10s\n" "$d" "ERROR" "ERROR" "ERROR" "ERROR" "ERROR"
            fi
        done
    done
    echo ""
else
    echo -e "${RED}❌ Build failed for SharedHashTable algorithm${NC}"
    echo ""
fi

# RootSplitting Algorithm Evaluation (depths 1-8, threads 2-8)
echo "=========================================="
echo -e "${GREEN}ROOT SPLITTING ALGORITHM EVALUATION${NC}"
echo "=========================================="
echo "Testing depths 1-8 with threads 2-8..."
echo ""

if build_algorithm "RootSplitting" "search-rs.cpp"; then
    echo -e "${BLUE}Algorithm: RootSplitting${NC}"
    
    for threads in {2..8}; do
        echo ""
        echo -e "${CYAN}--- Testing with $threads threads ---${NC}"
        printf "%-8s %-10s %-12s %-10s %-12s %-10s\n" "Depth" "Nodes" "Time(ms)" "NPS" "Score" "Best Move"
        echo "----------------------------------------------------------------"
        
        for depth in {1..8}; do
            result=$(run_evaluation "RootSplitting" $depth $threads)
            echo "$result" >> "$results_file"
            
            # Parse result for display
            IFS=',' read -r alg d th nodes time wall_time nps score move <<< "$result"
            if [[ "$nodes" != "ERROR" ]]; then
                printf "%-8s %-10s %-12s %-10s %-12s %-10s\n" "$d" "$nodes" "$time" "$nps" "$score" "$move"
            else
                printf "%-8s %-10s %-12s %-10s %-12s %-10s\n" "$d" "ERROR" "ERROR" "ERROR" "ERROR" "ERROR"
            fi
        done
    done
    echo ""
else
    echo -e "${RED}❌ Build failed for RootSplitting algorithm${NC}"
    echo ""
fi

# MPI Algorithm Evaluation (depths 1-8, processes 2-8)
if $MPI_AVAILABLE; then
    echo "=========================================="
    echo -e "${GREEN}MPI ALGORITHM EVALUATION${NC}"
    echo "=========================================="
    echo "Testing depths 1-8 with processes 2-8..."
    echo ""

    if build_algorithm "MPI" "search-mpi.cpp"; then
        echo -e "${BLUE}Algorithm: MPI${NC}"
        
        for processes in {2..8}; do
            echo ""
            echo -e "${CYAN}--- Testing with $processes processes ---${NC}"
            printf "%-8s %-10s %-12s %-10s %-12s %-10s\n" "Depth" "Nodes" "Time(ms)" "NPS" "Score" "Best Move"
            echo "----------------------------------------------------------------"
            
            for depth in {1..8}; do
                echo -n "    Running depth $depth with $processes processes... "
                start_eval_time=$(date +%s)
                result=$(run_evaluation "MPI" $depth $processes)
                end_eval_time=$(date +%s)
                eval_duration=$((end_eval_time - start_eval_time))
                
                echo "$result" >> "$results_file"
                
                # Parse result for display
                IFS=',' read -r alg d th nodes time wall_time nps score move <<< "$result"
                if [[ "$nodes" != "ERROR" ]]; then
                    printf "✅ %-8s %-10s %-12s %-10s %-12s %-10s\n" "$d" "$nodes" "$time" "$nps" "$score" "$move"
                else
                    printf "❌ %-8s %-10s %-12s %-10s %-12s %-10s\n" "$d" "ERROR" "ERROR" "ERROR" "ERROR" "ERROR"
                    echo "      Debug: MPI evaluation failed after ${eval_duration}s"
                    
                    # If multiple consecutive failures, skip remaining depths for this process count
                    if [[ $depth -gt 3 && "$nodes" == "ERROR" ]]; then
                        echo "      Skipping remaining depths for $processes processes due to repeated failures"
                        break
                    fi
                fi
            done
        done
        echo ""
    else
        echo -e "${RED}❌ Build failed for MPI algorithm${NC}"
        echo ""
    fi
fi

echo "=========================================="
echo -e "${GREEN}EVALUATION SUMMARY${NC}"
echo "=========================================="
echo ""
echo "📈 Complete results saved to: $results_file"
echo ""
echo "📊 Quick Analysis:"
echo "- Sequential: Tested depths 1-8 with 1 thread"
echo "- SharedHashTable: Tested depths 1-8 with threads 2-8 (49 tests)"
echo "- RootSplitting: Tested depths 1-8 with threads 2-8 (49 tests)"
if $MPI_AVAILABLE; then
    echo "- MPI: Tested depths 1-8 with processes 2-8 (49 tests)"
    echo "- Total tests: 155 evaluations"
else
    echo "- MPI: Skipped (not available)"
    echo "- Total tests: 106 evaluations"
fi
echo ""
echo "🔍 To analyze results:"
echo "  - View raw data: cat $results_file"
echo "  - Import into spreadsheet for graphs and analysis"
echo "  - Use scripts/analyze_results.py (if created) for automated analysis"
echo ""
echo "⚡ Performance Insights:"
echo "  - Check NPS (Nodes Per Second) for efficiency"
echo "  - Compare wall time vs engine time for overhead analysis"
echo "  - Look for optimal thread/process counts per depth"
echo "  - Analyze scaling efficiency across depths"
if $MPI_AVAILABLE; then
    echo "  - Compare MPI process scaling vs OpenMP thread scaling"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}EVALUATION COMPLETE${NC}"
echo "=========================================="
echo "Timestamp: $(date)"
echo "Results: $results_file"

# Restore original state
unset OMP_NUM_THREADS 