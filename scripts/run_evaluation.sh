#!/bin/bash

# Chess Engine Evaluation Launcher
# Provides an easy interface to run different evaluation scripts

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check MPI availability
check_mpi() {
    if command -v mpirun &> /dev/null && command -v mpic++ &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Display MPI status
display_mpi_status() {
    if check_mpi; then
        echo -e "${GREEN}✅ MPI detected:${NC} $(mpirun --version 2>/dev/null | head -n 1)"
    else
        echo -e "${YELLOW}⚠️  MPI not available${NC}"
        echo -e "   ${CYAN}MPI installation hints:${NC}"
        echo "   - Ubuntu/Debian: sudo apt-get install mpich libmpich-dev"
        echo "   - macOS: brew install mpich"
        echo "   - CentOS/RHEL: sudo yum install mpich mpich-devel"
        echo ""
        echo -e "   ${CYAN}Note:${NC} Evaluations will run without MPI tests"
    fi
}

echo "=========================================="
echo -e "${GREEN}🚀 CHESS ENGINE EVALUATION LAUNCHER${NC}"
echo "=========================================="
echo ""

# Display system info and MPI status
echo -e "${CYAN}System Information:${NC}"
echo "  OS: $(uname -s) $(uname -r) $(uname -m)"
echo "  Date: $(date)"
echo ""
display_mpi_status
echo ""

echo "Select the evaluation to run:"
echo ""
echo -e "${BLUE}1.${NC} Quick Comparison (compare_algorithms.sh)"
echo "   → General algorithm comparison and feature testing"
if check_mpi; then
    echo "   → Tests Sequential, SharedHashTable, RootSplitting, and MPI"
else
    echo "   → Tests Sequential, SharedHashTable, and RootSplitting (MPI skipped)"
fi
echo "   → Takes ~2-3 minutes"
echo ""
echo -e "${BLUE}2.${NC} Comprehensive Evaluation (depth_thread_evaluation.sh)"
echo "   → Systematic depth 1-8 and thread 2-8 testing"
if check_mpi; then
    echo "   → Tests all algorithms including MPI with processes 2-8"
    echo "   → Takes 20-40 minutes, generates CSV data (155 tests)"
else
    echo "   → Tests OpenMP algorithms only (MPI skipped)"
    echo "   → Takes 15-30 minutes, generates CSV data (106 tests)"
fi
echo ""
echo -e "${BLUE}3.${NC} Analyze Previous Results (analyze_results.py)"
echo "   → Load and analyze existing evaluation data"
echo "   → Requires previous depth_thread_evaluation run"
echo ""
echo -e "${BLUE}4.${NC} Install MPI"
echo "   → Show detailed MPI installation instructions"
echo ""
echo -e "${BLUE}5.${NC} View Documentation"
echo "   → Show README with detailed information"
echo ""
echo -e "${YELLOW}q.${NC} Quit"
echo ""
read -p "Enter your choice [1-5, q]: " choice

case $choice in
    1)
        echo ""
        echo -e "${CYAN}🔄 Running Quick Comparison...${NC}"
        echo ""
        ./scripts/compare_algorithms.sh
        ;;
    2)
        echo ""
        if check_mpi; then
            echo -e "${CYAN}📊 Running Comprehensive Evaluation (with MPI)...${NC}"
            echo "⚠️  This will take 20-40 minutes and run 155 tests"
        else
            echo -e "${CYAN}📊 Running Comprehensive Evaluation (without MPI)...${NC}"
            echo "⚠️  This will take 15-30 minutes and run 106 tests"
            echo "    (MPI tests skipped - install MPI for complete evaluation)"
        fi
        read -p "Continue? [y/N]: " confirm
        if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
            echo ""
            ./scripts/depth_thread_evaluation.sh
            echo ""
            echo -e "${GREEN}✅ Evaluation complete!${NC}"
            echo ""
            read -p "Analyze results now? [y/N]: " analyze
            if [[ $analyze == [yY] || $analyze == [yY][eE][sS] ]]; then
                echo ""
                echo -e "${CYAN}📈 Running Analysis...${NC}"
                if command -v python3 &> /dev/null; then
                    python3 scripts/analyze_results.py
                else
                    echo -e "${RED}❌ Python3 not found. Please install Python3 to run analysis.${NC}"
                fi
            fi
        else
            echo "Evaluation cancelled."
        fi
        ;;
    3)
        echo ""
        echo -e "${CYAN}📈 Running Analysis...${NC}"
        if command -v python3 &> /dev/null; then
            python3 scripts/analyze_results.py
        else
            echo -e "${RED}❌ Python3 not found. Please install Python3 to run analysis.${NC}"
            echo ""
            echo "Python installation hints:"
            echo "- Ubuntu/Debian: sudo apt-get install python3"
            echo "- macOS: brew install python3"
            echo "- CentOS/RHEL: sudo yum install python3"
        fi
        ;;
    4)
        echo ""
        echo -e "${CYAN}📦 MPI Installation Instructions${NC}"
        echo "=========================================="
        echo ""
        if check_mpi; then
            echo -e "${GREEN}✅ MPI is already installed!${NC}"
            echo "Current version: $(mpirun --version 2>/dev/null | head -n 1)"
        else
            echo -e "${YELLOW}Installing MPI (Message Passing Interface):${NC}"
            echo ""
            echo "Ubuntu/Debian:"
            echo "  sudo apt-get update"
            echo "  sudo apt-get install mpich libmpich-dev"
            echo ""
            echo "macOS (with Homebrew):"
            echo "  brew install mpich"
            echo ""
            echo "CentOS/RHEL/Fedora:"
            echo "  sudo yum install mpich mpich-devel"
            echo "  # or with dnf:"
            echo "  sudo dnf install mpich mpich-devel"
            echo ""
            echo "Arch Linux:"
            echo "  sudo pacman -S mpich"
            echo ""
            echo "After installation, you may need to:"
            echo "1. Restart your terminal"
            echo "2. Add MPI to your PATH (usually automatic)"
            echo "3. Verify installation with: mpirun --version"
            echo ""
            echo "Alternative MPI implementations:"
            echo "- OpenMPI: Usually available as 'openmpi' package"
            echo "- Intel MPI: Part of Intel oneAPI toolkit"
        fi
        echo ""
        ;;
    5)
        echo ""
        echo -e "${CYAN}📖 Documentation:${NC}"
        echo ""
        if [[ -f scripts/README.md ]]; then
            cat scripts/README.md
        else
            echo "README.md not found in scripts directory."
            echo ""
            echo "Available evaluation scripts:"
            echo "- compare_algorithms.sh: Quick comparison of all algorithms"
            echo "- depth_thread_evaluation.sh: Comprehensive performance evaluation"
            echo "- analyze_results.py: Data analysis and visualization"
        fi
        ;;
    q|Q)
        echo ""
        echo "Goodbye! 👋"
        exit 0
        ;;
    *)
        echo ""
        echo -e "${YELLOW}⚠️  Invalid choice. Please select 1-5 or q.${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}🎯 Evaluation launcher finished.${NC}" 