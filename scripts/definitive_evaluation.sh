#!/bin/bash

# Definitive Chess Engine Evaluation Script
# Comprehensive performance analysis launcher for all search algorithm implementations
# Author: Generated for HPC Laboratory Project
# Usage: ./definitive_evaluation.sh [options]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PYTHON_SCRIPT="$SCRIPT_DIR/definitive_evaluation.py"
RESULTS_DIR="$PROJECT_ROOT/results"

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

show_banner() {
    echo -e "${PURPLE}"
    cat << "EOF"
    ╔══════════════════════════════════════════════════════════╗
    ║          DEFINITIVE CHESS ENGINE EVALUATION             ║
    ║              Comprehensive Performance Analysis          ║
    ╚══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${CYAN}Testing 5 search algorithm implementations:${NC}"
    echo -e "  1. Sequential      - Single-threaded baseline"
    echo -e "  2. SharedHashTable - OpenMP shared transposition table"
    echo -e "  3. RootSplitting   - OpenMP root splitting parallelization"
    echo -e "  4. MPI             - Distributed parallel search"
    echo -e "  5. Hybrid          - Combined OpenMP+MPI approach"
    echo ""
    echo -e "${CYAN}Metrics analyzed:${NC}"
    echo -e "  • NPS (Nodes Per Second)     • Parallelization efficiency"
    echo -e "  • Speed-up ratios            • Computational efficiency"
    echo -e "  • Scalability analysis       • Load balancing effectiveness"
    echo ""
}

check_python_dependencies() {
    echo -e "${CYAN}🐍 Checking Python Dependencies...${NC}"
    
    # Check Python 3
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is required but not installed"
        echo "Installation instructions:"
        echo "  macOS:    brew install python3"
        echo "  Ubuntu:   sudo apt-get install python3"
        echo "  CentOS:   sudo yum install python3"
        return 1
    fi
    print_success "Python 3 found: $(python3 --version)"
    
    # Check required packages
    local required_packages=("pandas" "matplotlib" "seaborn" "numpy")
    local missing_packages=()
    
    for package in "${required_packages[@]}"; do
        if ! python3 -c "import $package" &> /dev/null; then
            missing_packages+=($package)
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        print_warning "Missing Python packages: ${missing_packages[*]}"
        echo ""
        echo -e "${CYAN}Installing missing packages...${NC}"
        
        # Try pip3 first, then pip
        if command -v pip3 &> /dev/null; then
            pip3 install "${missing_packages[@]}"
        elif command -v pip &> /dev/null; then
            pip install "${missing_packages[@]}"
        else
            print_error "pip/pip3 not found. Please install manually:"
            echo "  pip3 install ${missing_packages[*]}"
            return 1
        fi
        
        # Verify installation
        for package in "${missing_packages[@]}"; do
            if python3 -c "import $package" &> /dev/null; then
                print_success "$package installed successfully"
            else
                print_error "Failed to install $package"
                return 1
            fi
        done
    fi
    
    print_success "All Python dependencies satisfied"
    return 0
}

check_build_dependencies() {
    echo -e "${CYAN}🔨 Checking Build Dependencies...${NC}"
    
    # Check make
    if ! command -v make &> /dev/null; then
        print_error "make is required but not installed"
        echo "Installation instructions:"
        echo "  macOS:    xcode-select --install"
        echo "  Ubuntu:   sudo apt-get install build-essential"
        echo "  CentOS:   sudo yum groupinstall 'Development Tools'"
        return 1
    fi
    print_success "make found: $(make --version | head -1)"
    
    # Check C++ compiler
    if ! command -v clang++ &> /dev/null && ! command -v g++ &> /dev/null; then
        print_error "C++ compiler (clang++ or g++) is required"
        echo "Installation instructions:"
        echo "  macOS:    xcode-select --install"
        echo "  Ubuntu:   sudo apt-get install g++"
        echo "  CentOS:   sudo yum install gcc-c++"
        return 1
    fi
    
    if command -v clang++ &> /dev/null; then
        print_success "clang++ found: $(clang++ --version | head -1)"
    else
        print_success "g++ found: $(g++ --version | head -1)"
    fi
    
    # Check MPI (optional)
    if command -v mpirun &> /dev/null && command -v mpic++ &> /dev/null; then
        print_success "MPI found: $(mpirun --version | head -1)"
        echo -e "           📊 MPI and Hybrid algorithms will be tested"
    else
        print_warning "MPI not found - MPI and Hybrid tests will be skipped"
        echo "To install MPI:"
        echo "  macOS:    brew install mpich"
        echo "  Ubuntu:   sudo apt-get install mpich libmpich-dev"
        echo "  CentOS:   sudo yum install mpich mpich-devel"
    fi
    
    # Check OpenMP (optional but recommended)
    echo '#include <omp.h>
int main() { return omp_get_max_threads(); }' | clang++ -I/opt/homebrew/opt/libomp/include -Xclang -fopenmp -L/opt/homebrew/opt/libomp/lib -lomp -x c++ - -o /tmp/omp_test 2>/dev/null && rm -f /tmp/omp_test
    
    if [ $? -eq 0 ]; then
        print_success "OpenMP found - Parallel algorithms will be tested"
    else
        print_warning "OpenMP not detected - Some optimizations may not be available"
        echo "To install OpenMP on macOS: brew install libomp"
    fi
    
    return 0
}

check_project_structure() {
    echo -e "${CYAN}📁 Checking Project Structure...${NC}"
    
    # Navigate to project root
    cd "$PROJECT_ROOT"
    
    # Check required files
    local required_files=(
        "makefile"
        "Makefile.hybrid"
        "old-search.cpp"
        "search-sht.cpp"
        "search-rs.cpp"
        "search-mpi.cpp"
        "search-hybrid.cpp"
        "search.h"
        "main.cpp"
    )
    
    local missing_files=()
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_error "Missing required files:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        return 1
    fi
    
    print_success "All required project files found"
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    print_success "Results directory ready: $RESULTS_DIR"
    
    return 0
}

run_quick_test() {
    echo -e "${CYAN}🚀 Running Quick Test...${NC}"
    cd "$PROJECT_ROOT"
    
    if [ -f "$PYTHON_SCRIPT" ]; then
        python3 "$PYTHON_SCRIPT" --quick --output-dir "$RESULTS_DIR"
    else
        print_error "Python evaluation script not found: $PYTHON_SCRIPT"
        return 1
    fi
}

run_comprehensive_evaluation() {
    echo -e "${CYAN}🚀 Running Comprehensive Evaluation...${NC}"
    cd "$PROJECT_ROOT"
    
    if [ -f "$PYTHON_SCRIPT" ]; then
        python3 "$PYTHON_SCRIPT" --output-dir "$RESULTS_DIR"
    else
        print_error "Python evaluation script not found: $PYTHON_SCRIPT"
        return 1
    fi
}

analyze_existing_results() {
    echo -e "${CYAN}📊 Available Results Files:${NC}"
    
    if [ ! -d "$RESULTS_DIR" ]; then
        print_error "Results directory not found: $RESULTS_DIR"
        return 1
    fi
    
    local json_files=($(find "$RESULTS_DIR" -name "*.json" -type f | sort -r))
    
    if [ ${#json_files[@]} -eq 0 ]; then
        print_error "No results files found in $RESULTS_DIR"
        echo "Run an evaluation first with option 1 or 2"
        return 1
    fi
    
    echo "Select a results file to analyze:"
    for i in "${!json_files[@]}"; do
        local file="${json_files[$i]}"
        local basename=$(basename "$file")
        local size=$(du -h "$file" | cut -f1)
        echo "  $((i+1)). $basename ($size)"
    done
    
    echo -n "Enter choice [1-${#json_files[@]}]: "
    read choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#json_files[@]} ]; then
        local selected_file="${json_files[$((choice-1))]}"
        echo -e "${CYAN}Analyzing: $(basename "$selected_file")${NC}"
        cd "$PROJECT_ROOT"
        python3 "$PYTHON_SCRIPT" --analyze "$selected_file"
    else
        print_error "Invalid choice"
        return 1
    fi
}

generate_report() {
    echo -e "${CYAN}📋 Available Results Files:${NC}"
    
    if [ ! -d "$RESULTS_DIR" ]; then
        print_error "Results directory not found: $RESULTS_DIR"
        return 1
    fi
    
    local json_files=($(find "$RESULTS_DIR" -name "*.json" -type f | sort -r))
    
    if [ ${#json_files[@]} -eq 0 ]; then
        print_error "No results files found in $RESULTS_DIR"
        echo "Run an evaluation first with option 1 or 2"
        return 1
    fi
    
    echo "Select a results file to generate report from:"
    for i in "${!json_files[@]}"; do
        local file="${json_files[$i]}"
        local basename=$(basename "$file")
        local size=$(du -h "$file" | cut -f1)
        echo "  $((i+1)). $basename ($size)"
    done
    
    echo -n "Enter choice [1-${#json_files[@]}]: "
    read choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#json_files[@]} ]; then
        local selected_file="${json_files[$((choice-1))]}"
        echo -e "${CYAN}Generating report from: $(basename "$selected_file")${NC}"
        cd "$PROJECT_ROOT"
        python3 "$PYTHON_SCRIPT" --report "$selected_file"
    else
        print_error "Invalid choice"
        return 1
    fi
}

show_system_info() {
    print_header "SYSTEM INFORMATION"
    
    echo -e "${CYAN}Hardware:${NC}"
    if command -v sysctl &> /dev/null; then
        echo "  CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Unknown')"
        echo "  Cores: $(sysctl -n hw.ncpu 2>/dev/null || echo 'Unknown')"
    elif [ -f /proc/cpuinfo ]; then
        echo "  CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)"
        echo "  Cores: $(nproc)"
    else
        echo "  CPU: Unknown"
        echo "  Cores: Unknown"
    fi
    
    echo -e "\n${CYAN}Software:${NC}"
    echo "  OS: $(uname -s) $(uname -r)"
    echo "  Architecture: $(uname -m)"
    echo "  Shell: $SHELL"
    
    echo -e "\n${CYAN}Available Tools:${NC}"
    [ -x "$(command -v python3)" ] && echo "  ✅ Python: $(python3 --version)" || echo "  ❌ Python: Not found"
    [ -x "$(command -v make)" ] && echo "  ✅ Make: $(make --version | head -1)" || echo "  ❌ Make: Not found"
    [ -x "$(command -v clang++)" ] && echo "  ✅ Clang++: $(clang++ --version | head -1)" || echo "  ❌ Clang++: Not found"
    [ -x "$(command -v g++)" ] && echo "  ✅ G++: $(g++ --version | head -1)" || echo "  ❌ G++: Not found"
    [ -x "$(command -v mpirun)" ] && echo "  ✅ MPI: $(mpirun --version | head -1)" || echo "  ❌ MPI: Not found"
    
    echo ""
}

show_usage() {
    echo "Definitive Chess Engine Evaluation Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -q, --quick    Run quick evaluation only"
    echo "  -c, --check    Check dependencies only"
    echo "  -s, --system   Show system information"
    echo ""
    echo "Interactive Mode (default):"
    echo "  Run without options to enter interactive mode with menu"
    echo ""
    echo "Examples:"
    echo "  $0              # Interactive mode"
    echo "  $0 --quick      # Quick evaluation"
    echo "  $0 --check      # Check dependencies"
    echo "  $0 --system     # Show system info"
}

show_menu() {
    echo ""
    echo -e "${CYAN}Select an option:${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} Quick Evaluation (5-10 minutes)"
    echo "   → Test all algorithms with limited depth/thread combinations"
    echo "   → Good for initial testing and debugging"
    echo ""
    echo -e "${GREEN}2.${NC} Comprehensive Evaluation (30-60 minutes)"
    echo "   → Full systematic testing across all parameters"
    echo "   → Multiple positions, depths 3-8, threads 1-8"
    echo "   → Generates complete performance analysis"
    echo ""
    echo -e "${GREEN}3.${NC} Analyze Existing Results"
    echo "   → Load and analyze previously generated results"
    echo "   → Create visualizations and performance analysis"
    echo ""
    echo -e "${GREEN}4.${NC} Generate Report"
    echo "   → Create comprehensive markdown report"
    echo "   → Include tables, analysis, and recommendations"
    echo ""
    echo -e "${GREEN}5.${NC} Show System Information"
    echo "   → Display hardware and software details"
    echo "   → Check available tools and dependencies"
    echo ""
    echo -e "${YELLOW}q.${NC} Quit"
    echo ""
    echo -n "Enter your choice [1-5, q]: "
}

main() {
    # Parse command line arguments
    case "${1:-}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -q|--quick)
            show_banner
            if check_python_dependencies && check_build_dependencies && check_project_structure; then
                run_quick_test
            fi
            exit 0
            ;;
        -c|--check)
            show_banner
            check_python_dependencies
            check_build_dependencies
            check_project_structure
            exit 0
            ;;
        -s|--system)
            show_system_info
            exit 0
            ;;
        "")
            # Interactive mode
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    
    # Interactive mode
    show_banner
    
    # Initial dependency check
    echo -e "${CYAN}🔍 Performing initial dependency check...${NC}"
    if ! check_python_dependencies; then
        print_error "Python dependencies not satisfied"
        exit 1
    fi
    
    if ! check_build_dependencies; then
        print_error "Build dependencies not satisfied"
        exit 1
    fi
    
    if ! check_project_structure; then
        print_error "Project structure check failed"
        exit 1
    fi
    
    print_success "All systems ready for evaluation!"
    
    # Main interactive loop
    while true; do
        show_menu
        read choice
        
        case $choice in
            1)
                echo ""
                echo -e "${CYAN}🚀 Starting Quick Evaluation...${NC}"
                echo "This will take approximately 5-10 minutes"
                echo ""
                run_quick_test
                ;;
            2)
                echo ""
                echo -e "${CYAN}🚀 Starting Comprehensive Evaluation...${NC}"
                echo "⚠️  This will take 30-60 minutes and run extensive tests"
                echo ""
                echo -n "Continue? [y/N]: "
                read confirm
                if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
                    run_comprehensive_evaluation
                else
                    echo "Evaluation cancelled"
                fi
                ;;
            3)
                echo ""
                analyze_existing_results
                ;;
            4)
                echo ""
                generate_report
                ;;
            5)
                echo ""
                show_system_info
                ;;
            q|Q)
                echo ""
                echo -e "${GREEN}Thank you for using the Definitive Chess Engine Evaluation tool! 👋${NC}"
                exit 0
                ;;
            *)
                echo ""
                print_error "Invalid choice. Please select 1-5 or q."
                ;;
        esac
        
        # Pause before showing menu again
        echo ""
        echo -n "Press Enter to continue..."
        read
    done
}

# Make sure we're in the right directory
cd "$PROJECT_ROOT"

# Run main function with all arguments
main "$@" 