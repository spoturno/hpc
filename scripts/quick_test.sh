#!/bin/bash

# Quick Algorithm Comparison Script
# Fast comparison of all three search algorithms

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}⚡ QUICK CHESS ENGINE COMPARISON${NC}"
echo "================================="
echo

# Function to extract clean metrics
extract_clean_metrics() {
    local output="$1"
    local depth="$2"
    
    # Extract UCI info for specified depth
    local depth_line=$(echo "$output" | grep "depth $depth" | tail -1)
    local bestmove=$(echo "$output" | grep "bestmove" | tail -1 | cut -d' ' -f2)
    
    if [[ -n "$depth_line" ]]; then
        local score=$(echo "$depth_line" | grep -o "score [^[:space:]]* [^[:space:]]*" | cut -d' ' -f2-)
        local nodes=$(echo "$depth_line" | grep -o "nodes [0-9]*" | cut -d' ' -f2)
        local time=$(echo "$depth_line" | grep -o "time [0-9]*" | cut -d' ' -f2)
        local nps=$(echo "$depth_line" | grep -o "nps [0-9]*" | cut -d' ' -f2)
        
        echo "    Score: ${score:-N/A}"
        echo "    Best:  ${bestmove:-N/A}"
        echo "    Nodes: ${nodes:-N/A}"
        echo "    Time:  ${time:-N/A}ms"
        echo "    NPS:   ${nps:-N/A}"
    else
        echo "    ❌ No depth $depth analysis found"
    fi
    
    # Extract custom timing if available
    local duration=$(echo "$output" | grep "Duration:" | tail -1 | cut -d' ' -f2)
    local custom_nodes=$(echo "$output" | grep "Nodes:" | tail -1 | cut -d' ' -f2)
    
    if [[ -n "$duration" && -n "$custom_nodes" ]]; then
        echo "    📊 Custom: ${custom_nodes} nodes in ${duration}ms"
    fi
}

test_single() {
    local name=$1
    local file=$2
    
    echo -e "${YELLOW}Testing $name...${NC}"
    
    # Check if file exists
    if [[ ! -f "$file" ]]; then
        echo -e "  ${RED}❌ File $file not found${NC}"
        echo
        return 1
    fi
    
    # Link the search implementation
    if ! ln -sf "$file" search.cpp; then
        echo -e "  ${RED}❌ Failed to link $file${NC}"
        echo
        return 1
    fi
    
    # Clean and build
    if make clean > /dev/null 2>&1 && make > build.log 2>&1; then
        if [[ -f ./engine ]]; then
            echo -e "  ${GREEN}✅ Built successfully${NC}"
            
            # Test the engine with a reasonable timeout simulation
            echo "  🔍 Running analysis (depth 3)..."
            
            # Run engine test and capture all output
            engine_output=$(echo -e "uci\nposition startpos\ngo depth 3\nquit" | ./engine 2>&1)
            
            # Extract and display metrics
            extract_clean_metrics "$engine_output" "3"
            
        else
            echo -e "  ${RED}❌ Engine executable not created${NC}"
        fi
    else
        echo -e "  ${RED}❌ Build failed${NC}"
        if [[ -f build.log ]]; then
            echo "  Build errors:"
            tail -3 build.log | sed 's/^/    /'
        fi
    fi
    echo
}

# Function to compare algorithms side by side
compare_algorithms() {
    echo -e "${BLUE}📊 SIDE-BY-SIDE COMPARISON${NC}"
    echo "Depth 3 analysis on starting position:"
    echo
    
    algorithms=("old-search.cpp:Sequential" "search-sht.cpp:SharedHashTable" "search-rs.cpp:RootSplitting")
    
    printf "%-15s %-12s %-10s %-10s %-12s %-8s\n" "Algorithm" "Score" "Best Move" "Nodes" "Time(ms)" "NPS"
    printf "%-15s %-12s %-10s %-10s %-12s %-8s\n" "----------" "-----" "---------" "-----" "--------" "---"
    
    for alg in "${algorithms[@]}"; do
        IFS=':' read -r file name <<< "$alg"
        
        if [[ -f "$file" ]]; then
            ln -sf "$file" search.cpp
            if make clean > /dev/null 2>&1 && make > /dev/null 2>&1; then
                output=$(echo -e "uci\nposition startpos\ngo depth 3\nquit" | ./engine 2>&1)
                
                # Extract metrics for table
                depth_line=$(echo "$output" | grep "depth 3" | tail -1)
                if [[ -n "$depth_line" ]]; then
                    score=$(echo "$depth_line" | grep -o "score [^[:space:]]* [^[:space:]]*" | cut -d' ' -f2- | head -c 10)
                    nodes=$(echo "$depth_line" | grep -o "nodes [0-9]*" | cut -d' ' -f2)
                    time=$(echo "$depth_line" | grep -o "time [0-9]*" | cut -d' ' -f2)
                    nps=$(echo "$depth_line" | grep -o "nps [0-9]*" | cut -d' ' -f2)
                    bestmove=$(echo "$output" | grep "bestmove" | tail -1 | cut -d' ' -f2)
                    
                    printf "%-15s %-12s %-10s %-10s %-12s %-8s\n" \
                        "$name" "${score:-N/A}" "${bestmove:-N/A}" "${nodes:-N/A}" "${time:-N/A}" "${nps:-N/A}"
                else
                    printf "%-15s %-12s %-10s %-10s %-12s %-8s\n" \
                        "$name" "ERROR" "N/A" "N/A" "N/A" "N/A"
                fi
            else
                printf "%-15s %-12s %-10s %-10s %-12s %-8s\n" \
                    "$name" "BUILD FAIL" "N/A" "N/A" "N/A" "N/A"
            fi
        else
            printf "%-15s %-12s %-10s %-10s %-12s %-8s\n" \
                "$name" "NOT FOUND" "N/A" "N/A" "N/A" "N/A"
        fi
    done
    echo
}

# Main execution
echo "Testing all algorithms with depth 3 analysis..."
echo

# Test each algorithm individually
test_single "Sequential (Original)" "old-search.cpp"
test_single "Shared Hash Table" "search-sht.cpp"  
test_single "Root Splitting" "search-rs.cpp"

# Side-by-side comparison
compare_algorithms

echo -e "${GREEN}🎯 Quick test completed!${NC}"
echo
echo "For detailed analysis with parallel performance testing, run:"
echo -e "  ${BLUE}./compare_algorithms.sh${NC}"
echo
echo "Manual test commands:"
echo "  Sequential:        ln -sf old-search.cpp search.cpp && make"
echo "  Shared Hash Table: ln -sf search-sht.cpp search.cpp && make"  
echo "  Root Splitting:    ln -sf search-rs.cpp search.cpp && make"
echo

# Clean up
if [[ -f build.log ]]; then
    rm build.log
fi 