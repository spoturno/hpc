#!/bin/bash

# Test script for Hybrid OpenMP+MPI Chess Engine
# Usage: ./test_hybrid.sh [quick|medium|full|benchmark]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check if MPI is available
check_mpi() {
    if ! command -v mpirun &> /dev/null; then
        print_error "MPI not found. Please install OpenMPI or MPICH."
        exit 1
    fi
    print_success "MPI found: $(mpirun --version | head -1)"
}

# Check if OpenMP is available
check_openmp() {
    if ! echo '#include <omp.h>
    int main() { return omp_get_max_threads(); }' | clang++ -I/opt/homebrew/opt/libomp/include -Xclang -fopenmp -L/opt/homebrew/opt/libomp/lib -lomp -x c++ - -o /tmp/omp_test 2>/dev/null; then
        print_error "OpenMP not found. Please install OpenMP support with: brew install libomp"
        exit 1
    fi
    rm -f /tmp/omp_test
    print_success "OpenMP found"
}

# Build the hybrid engine
build_hybrid() {
    print_header "Building Hybrid Engine"
    
    if [ ! -f "Makefile.hybrid" ]; then
        print_error "Makefile.hybrid not found. Please ensure you're in the correct directory."
        exit 1
    fi
    
    make -f Makefile.hybrid clean
    if make -f Makefile.hybrid; then
        print_success "Hybrid engine built successfully"
    else
        print_error "Failed to build hybrid engine"
        exit 1
    fi
}

# Test configurations
test_single_process() {
    print_header "Testing Single Process (OpenMP only)"
    echo "This tests OpenMP parallelization within a single process"
    
    export OMP_NUM_THREADS=4
    echo "Running with OMP_NUM_THREADS=$OMP_NUM_THREADS"
    
    time mpirun -np 1 ./engine-hybrid 0 5
    print_success "Single process test completed"
}

test_multi_process() {
    print_header "Testing Multiple Processes (MPI + OpenMP)"
    echo "This tests the hybrid approach with multiple processes"
    
    export OMP_NUM_THREADS=2
    echo "Running with 4 processes, OMP_NUM_THREADS=$OMP_NUM_THREADS"
    
    time mpirun -np 4 ./engine-hybrid 1 5
    print_success "Multi-process test completed"
}

test_scalability() {
    print_header "Scalability Test"
    echo "Testing different process/thread combinations"
    
    local test_position=1
    local depth=5
    
    echo "Test position: $test_position, Depth: $depth"
    echo ""
    
    # 1 process, 8 threads
    echo "Configuration 1: 1 process × 8 threads"
    export OMP_NUM_THREADS=8
    time mpirun -np 1 ./engine-hybrid $test_position $depth
    echo ""
    
    # 2 processes, 4 threads each
    echo "Configuration 2: 2 processes × 4 threads"
    export OMP_NUM_THREADS=4
    time mpirun -np 2 ./engine-hybrid $test_position $depth
    echo ""
    
    # 4 processes, 2 threads each
    echo "Configuration 3: 4 processes × 2 threads"
    export OMP_NUM_THREADS=2
    time mpirun -np 4 ./engine-hybrid $test_position $depth
    echo ""
    
    # 8 processes, 1 thread each
    echo "Configuration 4: 8 processes × 1 thread"
    export OMP_NUM_THREADS=1
    time mpirun -np 8 ./engine-hybrid $test_position $depth
    
    print_success "Scalability test completed"
}

benchmark_implementations() {
    print_header "Benchmarking Against Other Implementations"
    
    local test_position=1
    local depth=6
    
    echo "Building other implementations for comparison..."
    
    # Function to build and test individual engines
    build_and_check_engine() {
        local name="$1"
        local search_file="$2"
        local use_mpi="$3"
        
        if [ "$use_mpi" = "true" ]; then
            if make -f makefile clean >/dev/null 2>&1 && make -f makefile engine-mpi >/dev/null 2>&1; then
                print_success "$name built"
                return 0
            else
                print_warning "Could not build $name"
                return 1
            fi
        else
            # Standard UCI engines: use symbolic linking approach
            if ln -sf "$search_file" search.cpp && make -f makefile clean >/dev/null 2>&1 && make -f makefile engine >/dev/null 2>&1; then
                print_success "$name built"
                return 0
            else
                print_warning "Could not build $name"
                return 1
            fi
        fi
    }
    
    # Build MPI engine
    if build_and_check_engine "MPI engine" "" "true"; then
        HAS_MPI_ENGINE=true
    else
        HAS_MPI_ENGINE=false
    fi
    
    # Build sequential engine
    if build_and_check_engine "Sequential engine" "old-search.cpp" "false"; then
        HAS_SEQUENTIAL=true
    else
        HAS_SEQUENTIAL=false
    fi
    
    # Build Root Split OpenMP engine
    if build_and_check_engine "Root Split OpenMP engine" "search-rs.cpp" "false"; then
        HAS_RS_ENGINE=true
    else
        HAS_RS_ENGINE=false
    fi
    
    # Build Shared Hash Table OpenMP engine
    if build_and_check_engine "Shared Hash Table OpenMP engine" "search-sht.cpp" "false"; then
        HAS_SHT_ENGINE=true
    else
        HAS_SHT_ENGINE=false
    fi
    
    echo ""
    echo "Running benchmarks with position $test_position, depth $depth:"
    echo ""
    
    # Convert test position to UCI format
    local test_fens=(
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
        "rnbqkb1r/pppppppp/5n2/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 1 2"
    )
    local fen="${test_fens[$test_position]}"
    
    # Function to run UCI engine with timeout
    run_uci_engine() {
        local engine_name="$1"
        local engine_path="$2"
        local threads="$3"
        
        echo "$engine_name (${threads} threads):"
        export OMP_NUM_THREADS=$threads
        
        local uci_commands="uci
isready
position fen $fen
go depth $depth
quit"
        
        local start_time=$(python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || echo $(($(date +%s) * 1000)))
        local output
        if command -v gtimeout &> /dev/null; then
            if output=$(echo -e "$uci_commands" | gtimeout 30s $engine_path 2>/dev/null); then
                local end_time=$(python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || echo $(($(date +%s) * 1000)))
                local wall_time=$((end_time - start_time))
                
                # Extract search information from output
                local bestmove=$(echo "$output" | grep "bestmove" | tail -1 | awk '{print $2}')
                local info_line=$(echo "$output" | grep "info.*depth $depth" | tail -1)
                
                if [ -n "$info_line" ]; then
                    local time_ms=$(echo "$info_line" | grep -o 'time [0-9]*' | awk '{print $2}')
                    local nodes=$(echo "$info_line" | grep -o 'nodes [0-9]*' | awk '{print $2}')
                    local nps=$(echo "$info_line" | grep -o 'nps [0-9]*' | awk '{print $2}')
                    local score=$(echo "$info_line" | grep -o 'score [^[:space:]]* [^[:space:]]*' | cut -d' ' -f2-)
                    
                    echo "info score ${score:-cp N/A} depth $depth time ${time_ms:-$wall_time} nodes ${nodes:-0} nps ${nps:-0} pv ${bestmove:-none}"
                    echo "Wall time: ${wall_time}ms"
                else
                    echo "No depth $depth line found. Available output:"
                    echo "$output" | grep "info.*depth" | head -3
                    echo "Best move: ${bestmove:-none}"
                fi
            else
                echo "Engine failed or timed out (gtimeout)"
            fi
        else
            # No timeout available, run directly with shorter test
            if output=$(echo -e "$uci_commands" | $engine_path 2>/dev/null); then
                local end_time=$(python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || echo $(($(date +%s) * 1000)))
                local wall_time=$((end_time - start_time))
                
                # Extract search information from output
                local bestmove=$(echo "$output" | grep "bestmove" | tail -1 | awk '{print $2}')
                local info_line=$(echo "$output" | grep "info.*depth $depth" | tail -1)
                
                if [ -n "$info_line" ]; then
                    local time_ms=$(echo "$info_line" | grep -o 'time [0-9]*' | awk '{print $2}')
                    local nodes=$(echo "$info_line" | grep -o 'nodes [0-9]*' | awk '{print $2}')
                    local nps=$(echo "$info_line" | grep -o 'nps [0-9]*' | awk '{print $2}')
                    local score=$(echo "$info_line" | grep -o 'score [^[:space:]]* [^[:space:]]*' | cut -d' ' -f2-)
                    
                    echo "info score ${score:-cp N/A} depth $depth time ${time_ms:-$wall_time} nodes ${nodes:-0} nps ${nps:-0} pv ${bestmove:-none}"
                    echo "Wall time: ${wall_time}ms"
                else
                    echo "No depth $depth line found. Available output:"
                    echo "$output" | grep "info.*depth" | head -3
                    echo "Best move: ${bestmove:-none}"
                fi
            else
                echo "Engine failed to run"
            fi
        fi
        echo ""
    }
    
    # Sequential baseline
    if [ "$HAS_SEQUENTIAL" = true ]; then
        # Re-link and rebuild for sequential
        ln -sf "old-search.cpp" search.cpp && make -f makefile clean >/dev/null 2>&1 && make -f makefile engine >/dev/null 2>&1
        run_uci_engine "Sequential (baseline)" "./engine" 1
    fi
    
    # Root Split OpenMP
    if [ "$HAS_RS_ENGINE" = true ]; then
        # Re-link and rebuild for root split
        ln -sf "search-rs.cpp" search.cpp && make -f makefile clean >/dev/null 2>&1 && make -f makefile engine >/dev/null 2>&1
        run_uci_engine "Root Split OpenMP" "./engine" 8
    fi
    
    # Shared Hash Table OpenMP
    if [ "$HAS_SHT_ENGINE" = true ]; then
        # Re-link and rebuild for shared hash table
        ln -sf "search-sht.cpp" search.cpp && make -f makefile clean >/dev/null 2>&1 && make -f makefile engine >/dev/null 2>&1
        run_uci_engine "Shared Hash Table OpenMP" "./engine" 8
    fi
    
    # Pure MPI
    if [ "$HAS_MPI_ENGINE" = true ]; then
        echo "Pure MPI (4 processes):"
        
        # Make sure MPI engine is built
        make -f makefile clean >/dev/null 2>&1 && make -f makefile engine-mpi >/dev/null 2>&1
        
        local uci_commands="uci
isready
position fen $fen
go depth $depth
quit"
        
        local start_time=$(python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || echo $(($(date +%s) * 1000)))
        local output
        if command -v gtimeout &> /dev/null; then
            if output=$(echo -e "$uci_commands" | gtimeout 30s mpirun -np 4 ./engine-mpi 2>/dev/null); then
                local end_time=$(python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || echo $(($(date +%s) * 1000)))
                local wall_time=$((end_time - start_time))
                
                local bestmove=$(echo "$output" | grep "bestmove" | tail -1 | awk '{print $2}')
                local info_line=$(echo "$output" | grep "info.*depth $depth" | tail -1)
                
                if [ -n "$info_line" ]; then
                    echo "$info_line"
                    echo "Wall time: ${wall_time}ms"
                else
                    echo "No depth $depth line found. Available output:"
                    echo "$output" | grep "info.*depth" | head -3
                    echo "Best move: ${bestmove:-none}"
                fi
            else
                echo "MPI engine failed or timed out (gtimeout)"
            fi
        else
            # No timeout available, run directly
            if output=$(echo -e "$uci_commands" | mpirun -np 4 ./engine-mpi 2>/dev/null); then
                local end_time=$(python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || echo $(($(date +%s) * 1000)))
                local wall_time=$((end_time - start_time))
                
                local bestmove=$(echo "$output" | grep "bestmove" | tail -1 | awk '{print $2}')
                local info_line=$(echo "$output" | grep "info.*depth $depth" | tail -1)
                
                if [ -n "$info_line" ]; then
                    echo "$info_line"
                    echo "Wall time: ${wall_time}ms"
                else
                    echo "No depth $depth line found. Available output:"
                    echo "$output" | grep "info.*depth" | head -3
                    echo "Best move: ${bestmove:-none}"
                fi
            else
                echo "MPI engine failed to run"
            fi
        fi
        echo ""
    fi
    
    # Hybrid OpenMP+MPI
    echo "Hybrid OpenMP+MPI (4 processes × 2 threads):"
    export OMP_NUM_THREADS=2
    time mpirun -np 4 ./engine-hybrid $test_position $depth
    echo ""
    
    # Clean up any symbolic links created during benchmarks
    if [ -L search.cpp ]; then
        rm -f search.cpp
    fi
    
    print_success "Benchmark completed"
}

stress_test() {
    print_header "Stress Test"
    echo "Running extended search on complex position"
    
    export OMP_NUM_THREADS=2
    echo "Configuration: 4 processes × 2 threads, depth 7"
    
    # Complex middlegame position
    time mpirun -np 4 ./engine-hybrid 1 7
    
    print_success "Stress test completed"
}

cleanup() {
    print_header "Cleanup"
    # Kill any hanging processes
    pkill -f engine-mpi 2>/dev/null || true
    pkill -f engine-hybrid 2>/dev/null || true
    pkill -f engine 2>/dev/null || true
    pkill -f mpirun 2>/dev/null || true
    
    make -f Makefile.hybrid clean 2>/dev/null || true
    make -f makefile clean 2>/dev/null || true
    rm -f engine engine-mpi 2>/dev/null || true
    rm -f *.o 2>/dev/null || true  # Clean up any leftover object files
    
    # Remove symbolic link to search.cpp if it exists
    if [ -L search.cpp ]; then
        rm -f search.cpp
    fi
    
    print_success "Cleanup completed"
}

show_help() {
    echo "Hybrid OpenMP+MPI Chess Engine Test Script"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  quick      - Quick test (single + multi process)"
    echo "  medium     - Medium test (includes scalability)"
    echo "  full       - Full test suite (includes benchmarks)"
    echo "  benchmark  - Only run benchmarks"
    echo "  stress     - Extended stress test"
    echo "  clean      - Clean build artifacts"
    echo "  help       - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 quick"
    echo "  $0 benchmark"
    echo "  OMP_NUM_THREADS=4 mpirun -np 2 ./engine-hybrid 0 6"
    echo ""
    echo "Engine Interfaces:"
    echo "  Hybrid:    Uses command-line args: ./engine-hybrid [position] [depth]"
    echo "  Others:    Use UCI protocol: echo 'uci\\nposition fen...\\ngo depth X\\nquit' | ./engine"
}

main() {
    local test_type=${1:-medium}
    
    case $test_type in
        "help"|"-h"|"--help")
            show_help
            exit 0
            ;;
        "clean")
            cleanup
            exit 0
            ;;
        "quick")
            check_mpi
            check_openmp
            build_hybrid
            test_single_process
            test_multi_process
            ;;
        "medium")
            check_mpi
            check_openmp
            build_hybrid
            test_single_process
            test_multi_process
            test_scalability
            ;;
        "full")
            check_mpi
            check_openmp
            build_hybrid
            test_single_process
            test_multi_process
            test_scalability
            benchmark_implementations
            ;;
        "benchmark")
            check_mpi
            check_openmp
            build_hybrid
            benchmark_implementations
            ;;
        "stress")
            check_mpi
            check_openmp
            build_hybrid
            stress_test
            ;;
        *)
            print_error "Unknown option: $test_type"
            show_help
            exit 1
            ;;
    esac
    
    print_header "All Tests Completed Successfully!"
    echo "For more advanced usage, see docs/4_HYBRID_OMP_MPI.md"
}

# Run main function with all arguments
main "$@" 