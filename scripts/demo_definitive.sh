#!/bin/bash

# Demo script for the Definitive Chess Engine Evaluation System
# This script demonstrates the capabilities and features

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        DEFINITIVE EVALUATION SYSTEM DEMO                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}This demonstration will show you the key features of the${NC}"
echo -e "${CYAN}Definitive Chess Engine Evaluation System${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "scripts/definitive_evaluation.sh" ]; then
    echo "❌ Please run this demo from the project root directory"
    exit 1
fi

echo -e "${GREEN}1. System Check${NC}"
echo -e "   Let's check what dependencies are available on your system:"
echo ""
./scripts/definitive_evaluation.sh --system
echo ""

echo -e "${GREEN}2. Dependency Check${NC}"
echo -e "   Let's verify all required dependencies are satisfied:"
echo ""
./scripts/definitive_evaluation.sh --check
echo ""

echo -e "${GREEN}3. Interactive Mode Preview${NC}"
echo -e "   The main evaluation system has an interactive menu:"
echo ""
echo -e "${CYAN}   To access the full interactive mode, run:${NC}"
echo -e "   ${YELLOW}./scripts/definitive_evaluation.sh${NC}"
echo ""
echo -e "   Available options:"
echo -e "   • Quick Evaluation (5-10 minutes)"
echo -e "   • Comprehensive Evaluation (30-60 minutes)"
echo -e "   • Analyze Existing Results"
echo -e "   • Generate Reports"
echo -e "   • System Information"
echo ""

echo -e "${GREEN}4. Command Line Options${NC}"
echo -e "   You can also use the system from command line:"
echo ""
echo -e "   ${CYAN}Quick evaluation:${NC}"
echo -e "   ${YELLOW}./scripts/definitive_evaluation.sh --quick${NC}"
echo ""
echo -e "   ${CYAN}Check dependencies:${NC}"
echo -e "   ${YELLOW}./scripts/definitive_evaluation.sh --check${NC}"
echo ""
echo -e "   ${CYAN}Show help:${NC}"
echo -e "   ${YELLOW}./scripts/definitive_evaluation.sh --help${NC}"
echo ""

echo -e "${GREEN}5. Direct Python Usage${NC}"
echo -e "   Advanced users can call the Python script directly:"
echo ""
echo -e "   ${CYAN}Full evaluation:${NC}"
echo -e "   ${YELLOW}python3 scripts/definitive_evaluation.py${NC}"
echo ""
echo -e "   ${CYAN}Quick evaluation:${NC}"
echo -e "   ${YELLOW}python3 scripts/definitive_evaluation.py --quick${NC}"
echo ""
echo -e "   ${CYAN}Analyze results:${NC}"
echo -e "   ${YELLOW}python3 scripts/definitive_evaluation.py --analyze results/file.json${NC}"
echo ""

echo -e "${GREEN}6. What Gets Tested${NC}"
echo -e "   The system evaluates five search algorithms:"
echo ""
echo -e "   • ${CYAN}Sequential${NC}      - Single-threaded baseline"
echo -e "   • ${CYAN}SharedHashTable${NC} - OpenMP shared transposition table"
echo -e "   • ${CYAN}RootSplitting${NC}   - OpenMP root splitting"
echo -e "   • ${CYAN}MPI${NC}             - Distributed parallel search"
echo -e "   • ${CYAN}Hybrid${NC}          - Combined OpenMP+MPI"
echo ""

echo -e "${GREEN}7. Metrics Analyzed${NC}"
echo -e "   The evaluation provides comprehensive analysis:"
echo ""
echo -e "   • ${CYAN}NPS (Nodes Per Second)${NC}     - Primary performance metric"
echo -e "   • ${CYAN}Parallelization Efficiency${NC} - Resource utilization"
echo -e "   • ${CYAN}Speed-up Ratios${NC}            - vs sequential baseline"
echo -e "   • ${CYAN}Scalability Analysis${NC}       - Thread scaling behavior"
echo -e "   • ${CYAN}Load Balancing${NC}             - Work distribution"
echo ""

echo -e "${GREEN}8. Output Files${NC}"
echo -e "   Results are saved in the results/ directory:"
echo ""
echo -e "   ${CYAN}Data Files:${NC}"
echo -e "   • definitive_evaluation_YYYYMMDD_HHMMSS.json - Raw results"
echo ""
echo -e "   ${CYAN}Visualizations:${NC}"
echo -e "   • *_performance_overview.png - Overall comparison"
echo -e "   • *_scalability_analysis.png - Parallel scaling"
echo -e "   • *_efficiency_heatmaps.png - Thread efficiency"
echo -e "   • *_algorithm_comparison.png - Detailed comparison"
echo ""
echo -e "   ${CYAN}Reports:${NC}"
echo -e "   • *_report.md - Comprehensive markdown report"
echo ""

echo -e "${GREEN}9. Evaluation Modes${NC}"
echo ""
echo -e "   ${CYAN}Quick Mode (5-10 minutes):${NC}"
echo -e "   • Tests starting position only"
echo -e "   • Depths: 4, 6"
echo -e "   • Thread counts: 1, 4, 8"
echo -e "   • Good for testing and debugging"
echo ""
echo -e "   ${CYAN}Comprehensive Mode (30-60 minutes):${NC}"
echo -e "   • Tests 4 different chess positions"
echo -e "   • Depths: 3, 4, 5, 6, 7, 8"
echo -e "   • Thread counts: 1, 2, 4, 6, 8"
echo -e "   • Complete systematic analysis"
echo ""

echo -e "${GREEN}10. Example Workflow${NC}"
echo ""
echo -e "    ${CYAN}Step 1:${NC} Check dependencies"
echo -e "    ${YELLOW}./scripts/definitive_evaluation.sh --check${NC}"
echo ""
echo -e "    ${CYAN}Step 2:${NC} Run quick evaluation to test"
echo -e "    ${YELLOW}./scripts/definitive_evaluation.sh --quick${NC}"
echo ""
echo -e "    ${CYAN}Step 3:${NC} Run comprehensive evaluation"
echo -e "    ${YELLOW}./scripts/definitive_evaluation.sh${NC}"
echo -e "    Then select option 2 (Comprehensive Evaluation)"
echo ""
echo -e "    ${CYAN}Step 4:${NC} Analyze results and generate reports"
echo -e "    (Analysis happens automatically after evaluation)"
echo ""

echo -e "${GREEN}11. Tips for Best Results${NC}"
echo ""
echo -e "   • Ensure stable system conditions (no other heavy processes)"
echo -e "   • Use comprehensive mode for final research results"
echo -e "   • Check multiple evaluation runs for consistency"
echo -e "   • Review generated reports for optimization insights"
echo ""

echo -e "${GREEN}12. Ready to Start?${NC}"
echo ""
echo -n "Would you like to run a quick evaluation now? [y/N]: "
read response

if [[ $response == [yY] || $response == [yY][eE][sS] ]]; then
    echo ""
    echo -e "${CYAN}🚀 Starting Quick Evaluation Demo...${NC}"
    echo ""
    ./scripts/definitive_evaluation.sh --quick
else
    echo ""
    echo -e "${CYAN}Demo completed!${NC}"
    echo ""
    echo -e "To start using the evaluation system:"
    echo -e "  ${YELLOW}./scripts/definitive_evaluation.sh${NC}"
    echo ""
    echo -e "For detailed documentation:"
    echo -e "  ${YELLOW}cat scripts/README_DEFINITIVE.md${NC}"
fi

echo ""
echo -e "${GREEN}Thank you for exploring the Definitive Chess Engine Evaluation System! 🎯${NC}" 