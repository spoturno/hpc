#!/bin/bash

# Chess Engine Algorithm Comparison Script
# Compares Sequential, Shared Hash Table, and Root Splitting algorithms

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
        # Fallback: run without timeout but with shorter tests
        $command
    fi
}

# Function to build algorithm
build_algorithm() {
    local name="$1"
    local file="$2"
    
    if [[ "$name" == "MPI" ]]; then
        if command -v mpirun &> /dev/null; then
            if make clean > /dev/null 2>&1 && make engine-mpi > /dev/null 2>&1; then
                return 0
            else
                return 1
            fi
        else
            echo "⚠️  MPI not available"
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

# Function to run engine with proper command
run_engine() {
    local name="$1"
    local command="$2"
    
    if [[ "$name" == "MPI" ]]; then
        if command -v mpirun &> /dev/null; then
            echo -e "$command" | mpirun -np 4 ./engine-mpi 2>&1
        else
            echo "MPI not available"
            return 1
        fi
    else
        echo -e "$command" | ./engine 2>&1
    fi
}

echo "=========================================="
echo "  CHESS ENGINE ALGORITHM COMPARISON"
echo "=========================================="
echo "Testing Date: $(date)"
echo "System: $(uname -s) $(uname -r) $(uname -m)"
echo ""
echo "🎯 Starting comprehensive algorithm comparison..."

# Test configurations
declare -a algorithms=("Sequential" "SharedHashTable" "RootSplitting" "MPI")
declare -a descriptions=("Single-threaded baseline implementation" "Parallel search with shared transposition table" "Parallel search with root splitting approach" "Distributed parallel search using MPI")
declare -a files=("old-search.cpp" "search-sht.cpp" "search-rs.cpp" "search-mpi.cpp")

# Function to run a single test
run_test() {
    local cmd="$1"
    local description="$2"
    local algorithm_name="$3"
    echo "🧪 $description"
    echo "Command: $cmd"
    
    # Use proper UCI protocol with initialization and termination
    result=$(run_engine "$algorithm_name" "uci\n$cmd\nquit")
    
    info_line=$(echo "$result" | grep "info.*depth" | tail -n 1)
    bestmove_line=$(echo "$result" | grep "bestmove" | head -n 1)
    
    if [[ -n "$info_line" ]]; then
        echo "    Last search info: $info_line"
    fi
    if [[ -n "$bestmove_line" ]]; then
        echo "    Best move: $bestmove_line"
    fi
    if [[ -z "$info_line" && -z "$bestmove_line" ]]; then
        echo "    Error or no output received"
    fi
    echo ""
}

# Function to test algorithm performance  
test_algorithm() {
    local name="$1"
    local desc="$2"
    local file="$3"
    
    echo "----------------------------------------"
    echo "Testing: $name"
    echo "Description: $desc"
    echo "File: $file"
    echo "----------------------------------------"
    
    echo "Building $name..."
    
    if build_algorithm "$name" "$file"; then
        if [[ "$name" == "MPI" ]]; then
            echo "✅ MPI build successful"
        else
            echo "✅ Build successful"
        fi
    else
        if [[ "$name" == "MPI" ]]; then
            echo "❌ MPI build failed"
            echo "Make sure MPI is installed and mpic++ is available"
        else
            echo "❌ Build failed for $name"
        fi
        return
    fi
    echo ""
    
    # Standard tests
    run_test "position startpos\ngo depth 4" "Test 1: Starting Position Analysis (depth 4)" "$name"
    run_test "position fen rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1 moves e7e5 g1f3 b8c6\ngo depth 3" "Test 2: Complex Position Analysis (depth 3)" "$name"
        
    # Sample performance test
    echo "🧪 Test 3: Sample Performance Test"
    echo "Running sample positions..."
    echo "Sample results:"
    
    # Test a few different positions
    local test_positions=(
        "r6r/1b2k1bq/8/8/7B/8/8/R3K2R b KQ - 3 2"
        "r1bqkbnr/pppppppp/n7/8/8/P7/1PPPPPPP/RNBQKBNR w KQkq - 2 2"
        "r3k2r/p1pp1pb1/bn2Qnp1/2qPN3/1p2P3/2N5/PPPBBPPP/R3K2R b KQkq - 3 2"
    )
    
    for fen in "${test_positions[@]}"; do
        result=$(run_engine "$name" "uci\nposition fen $fen\ngo depth 2\nquit")
        bestmove_line=$(echo "$result" | grep "bestmove" | head -n 1)
        if [[ -n "$bestmove_line" ]]; then
            echo "    FEN: $fen"
            echo "    Best Move: $(echo $bestmove_line | awk '{print $2}')"
        fi
    done
    echo ""
    
    echo "✅ $name testing completed"
    echo ""
}

# Test all algorithms
for i in "${!algorithms[@]}"; do
    test_algorithm "${algorithms[$i]}" "${descriptions[$i]}" "${files[$i]}"
done

echo "=========================================="
echo "  DEEP SEARCH ANALYSIS"
echo "=========================================="
echo ""
echo "🔍 Testing deeper searches to reveal parallel benefits..."

for i in "${!algorithms[@]}"; do
    echo "----------------------------------------"
    echo "Deep Search Test: ${algorithms[$i]}"
    echo "----------------------------------------"
    
    if build_algorithm "${algorithms[$i]}" "${files[$i]}"; then
        echo "Testing depths 5-7 on starting position..."
        
        for depth in 5 6 7; do
            echo "  Depth $depth:"
            start_time=$(date +%s%N)
            result=$(run_engine "${algorithms[$i]}" "uci\nposition startpos\ngo depth $depth\nquit")
            end_time=$(date +%s%N)
            wall_time=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
            
            info_line=$(echo "$result" | grep "info.*depth.*$depth" | tail -n 1)
            bestmove_line=$(echo "$result" | grep "bestmove" | head -n 1)
            
            if [[ -n "$info_line" ]]; then
                echo "        Search info: $info_line"
                echo "        Wall Time: ${wall_time}ms"
            elif [[ -n "$bestmove_line" ]]; then
                echo "        Best move: $bestmove_line (no info line found)"
                echo "        Wall Time: ${wall_time}ms"
            else
                echo "        Timeout or error at depth $depth"
            fi
        done
        echo ""
    else
        echo "Build failed for ${algorithms[$i]}"
        echo ""
    fi
done

echo "=========================================="
echo "  MOVE CONSISTENCY ANALYSIS"
echo "=========================================="
echo ""
echo "🎯 Checking if algorithms find consistent best moves..."

test_position="rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
echo "Testing position: Starting position"
echo "Expected strong moves: e2e4, d2d4, g1f3, b1c3"
echo ""

for i in "${!algorithms[@]}"; do
    echo "${algorithms[$i]}:"
    if build_algorithm "${algorithms[$i]}" "${files[$i]}"; then
        for depth in 3 4 5; do
            result=$(run_engine "${algorithms[$i]}" "uci\nposition fen $test_position\ngo depth $depth\nquit")
            bestmove_line=$(echo "$result" | grep "bestmove" | head -n 1)
            if [[ -n "$bestmove_line" ]]; then
                move=$(echo $bestmove_line | awk '{print $2}')
                echo "    Depth $depth: $move"
            else
                echo "    Depth $depth: timeout/error"
            fi
        done
    else
        echo "    Build failed"
    fi
    echo ""
done

echo "=========================================="
echo "  NODE COUNT EFFICIENCY ANALYSIS"
echo "=========================================="
echo ""
echo "📊 Analyzing node counts for search efficiency..."

tactical_position="r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 4 4"
echo "Testing tactical position (Italian Game): $tactical_position"
echo ""

for i in "${!algorithms[@]}"; do
    echo "${algorithms[$i]} Node Analysis:"
    if build_algorithm "${algorithms[$i]}" "${files[$i]}"; then
        for depth in 3 4; do
            echo "  Depth $depth:"
            result=$(run_engine "${algorithms[$i]}" "uci\nposition fen $tactical_position\ngo depth $depth\nquit")
            info_line=$(echo "$result" | grep "info.*depth.*$depth" | tail -n 1)
            if [[ -n "$info_line" ]]; then
                nodes=$(echo $info_line | grep -o 'nodes [0-9]*' | awk '{print $2}')
                time=$(echo $info_line | grep -o 'time [0-9]*' | awk '{print $2}')
                nps=$(echo $info_line | grep -o 'nps [0-9]*' | awk '{print $2}')
                best=$(echo $info_line | grep -o 'pv [a-h][1-8][a-h][1-8][a-z]*' | awk '{print $2}')
                echo "    Nodes: $nodes, Time: ${time}ms, NPS: $nps, Best: $best"
            else
                echo "    Timeout or error"
            fi
        done
    else
        echo "    Build failed"
    fi
    echo ""
done

echo "=========================================="
echo "  MEMORY AND RESOURCE USAGE"
echo "=========================================="
echo ""
echo "🖥️  Testing resource consumption..."

for i in "${!algorithms[@]}"; do
    echo "Resource Test: ${algorithms[$i]}"
    if build_algorithm "${algorithms[$i]}" "${files[$i]}"; then
        echo "  Running depth 5 search with resource monitoring..."
        
        # For MPI, we need different monitoring approach
        if [[ "${algorithms[$i]}" == "MPI" ]]; then
            (time mpirun -np 4 ./engine-mpi <<< "uci
position startpos
go depth 5
quit" > /dev/null) 2> temp_resource_$i.txt
        else
            (time ./engine <<< "uci
position startpos
go depth 5
quit" > /dev/null) 2> temp_resource_$i.txt
        fi
        
        if [[ -f temp_resource_$i.txt ]]; then
            echo "  Resource usage:"
            grep -E "(real|user|sys|maximum resident)" temp_resource_$i.txt | sed 's/^/    /'
            rm -f temp_resource_$i.txt
        fi
    else
        echo "  Build failed"
    fi
    echo ""
done

echo "=========================================="
echo "  PARALLEL PERFORMANCE ANALYSIS"
echo "=========================================="

# Test parallel performance with different thread counts
for parallel_algo in "SharedHashTable" "RootSplitting"; do
    algo_index=-1
    for i in "${!algorithms[@]}"; do
        if [[ "${algorithms[$i]}" == "$parallel_algo" ]]; then
            algo_index=$i
            break
        fi
    done
    
    if [[ $algo_index -ge 0 ]]; then
        echo ""
        echo "🔀 Parallel Performance Test: $parallel_algo"
        echo "Testing with different OpenMP thread counts..."
        
        if build_algorithm "${algorithms[$algo_index]}" "${files[$algo_index]}"; then
            for threads in 1 2 4 8; do
                echo "  Threads=$threads:"
                export OMP_NUM_THREADS=$threads
                result=$(run_engine "${algorithms[$algo_index]}" "uci\nposition startpos\ngo depth 3\nquit")
                info_line=$(echo "$result" | grep "info.*depth.*3" | tail -n 1)
                if [[ -n "$info_line" ]]; then
                    echo "        $info_line"
                else
                    echo "        Error or timeout"
                fi
            done
        else
            echo "Build failed for $parallel_algo"
        fi
    fi
done

echo "=========================================="
echo "  ALGORITHM STABILITY TEST"
echo "=========================================="
echo ""
echo "🔄 Testing result consistency across multiple runs..."

stable_position="rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
echo "Testing 5 runs of each algorithm on starting position (depth 4)..."
echo ""

for i in "${!algorithms[@]}"; do
    echo "${algorithms[$i]} Stability:"
    if build_algorithm "${algorithms[$i]}" "${files[$i]}"; then
        declare -a moves
        declare -a node_counts
        
        for run in {1..5}; do
            result=$(run_engine "${algorithms[$i]}" "uci\nposition fen $stable_position\ngo depth 4\nquit")
            best_move=$(echo "$result" | grep "bestmove" | head -n 1 | awk '{print $2}')
            nodes=$(echo "$result" | grep "info.*depth.*4" | tail -n 1 | grep -o 'nodes [0-9]*' | awk '{print $2}')
            
            moves[$run]=$best_move
            node_counts[$run]=$nodes
            echo "    Run $run: Move=$best_move, Nodes=$nodes"
        done
        
        # Check consistency
        first_move=${moves[1]}
        consistent_moves=true
        for move in "${moves[@]}"; do
            if [[ "$move" != "$first_move" ]]; then
                consistent_moves=false
                break
            fi
        done
        
        if $consistent_moves; then
            echo "    ✅ Move selection is consistent"
        else
            echo "    ⚠️  Move selection varies between runs"
        fi
        
        # Check node count variance
        min_nodes=$(printf '%s\n' "${node_counts[@]}" | sort -n | head -n1)
        max_nodes=$(printf '%s\n' "${node_counts[@]}" | sort -n | tail -n1)
        if [[ -n "$min_nodes" && -n "$max_nodes" && "$min_nodes" -gt 0 ]]; then
            variance_pct=$(( (max_nodes - min_nodes) * 100 / min_nodes ))
            echo "    Node count variance: ${variance_pct}% (range: $min_nodes-$max_nodes)"
        fi
    else
        echo "    Build failed"
    fi
    echo ""
done

echo "=========================================="
echo "  COMPREHENSIVE BENCHMARK"
echo "=========================================="

echo ""
echo "Running standardized benchmark (depth 3, starting position)..."
echo ""

for i in "${!algorithms[@]}"; do
    echo "⚡ ${algorithms[$i]}:"
    if build_algorithm "${algorithms[$i]}" "${files[$i]}"; then
        result=$(run_engine "${algorithms[$i]}" "uci\nposition startpos\ngo depth 3\nquit")
        info_line=$(echo "$result" | grep "info.*depth.*3" | tail -n 1)
        if [[ -n "$info_line" ]]; then
            echo "      $info_line"
        else
            echo "      Error or timeout"
        fi
    else
        echo "      Build failed"
    fi
    echo ""
done

echo "=========================================="
echo "  PERFORMANCE RECOMMENDATIONS"
echo "=========================================="
echo ""
echo "📋 Analysis Summary:"
echo ""

# Restore original state
ln -sf search.cpp search.cpp 2>/dev/null || true

echo "1. Node Count Analysis:"
echo "   - Check if parallel versions are doing redundant work"
echo "   - Verify move ordering consistency between implementations"
echo "   - Consider if shared data structures are causing conflicts"
echo ""
echo "2. Thread Scaling Issues:"
echo "   - Overhead dominates at shallow depths - test deeper searches"
echo "   - Consider work-stealing vs static partitioning"
echo "   - Profile for contention in shared data structures"
echo ""
echo "3. Search Consistency:"
echo "   - Different best moves suggest algorithmic differences"
echo "   - Verify deterministic behavior within each algorithm"
echo "   - Check if race conditions affect search order"
echo ""
echo "4. Optimization Opportunities:"
echo "   - Focus on deeper searches where parallelism pays off"
echo "   - Implement better load balancing"
echo "   - Consider hybrid approaches for different search depths"

echo "=========================================="
echo "  COMPARISON COMPLETE"
echo "=========================================="
echo "Timestamp: $(date)"
echo "To re-run: ./compare_algorithms.sh"
echo ""
echo "To manually test individual algorithms:"
echo "  Sequential:        ln -sf old-search.cpp search.cpp && make"
echo "  Shared Hash Table: ln -sf search-sht.cpp search.cpp && make"
echo "  Root Splitting:    ln -sf search-rs.cpp search.cpp && make"
echo "  MPI:               make engine-mpi && mpirun -np 4 ./engine-mpi" 