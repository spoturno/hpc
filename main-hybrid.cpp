#include <iostream>
#include <mpi.h>
#include <omp.h>
#include <chrono>

#include "libchess/Position.h"
#include "search.h"
#include "evaluation.h"

using namespace libchess;
using namespace search;

int main(int argc, char* argv[]) {
    // Initialize MPI
    int provided;
    MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);
    
    if (provided < MPI_THREAD_FUNNELED) {
        std::cerr << "Warning: MPI does not support thread safety level required for OpenMP+MPI hybrid" << std::endl;
    }
    
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    
    if (rank == 0) {
        std::cout << "Hybrid OpenMP+MPI Chess Engine" << std::endl;
        std::cout << "MPI Processes: " << size << std::endl;
        std::cout << "OpenMP Threads per process: " << omp_get_max_threads() << std::endl;
        std::cout << "Total parallel units: " << size * omp_get_max_threads() << std::endl;
        std::cout << "----------------------------------------" << std::endl;
        
        // Test position - starting position
        Position pos(constants::STARTPOS_FEN);
        
        // Alternative test positions
        std::vector<std::string> test_positions = {
            constants::STARTPOS_FEN,
            "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", // Complex middle game
            "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", // Endgame position
            "rnbqkb1r/pppppppp/5n2/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 1 2" // After 1.e4 Nf6
        };
        
        int test_case = 0;
        if (argc > 1) {
            test_case = std::min(std::max(0, std::atoi(argv[1])), (int)test_positions.size() - 1);
        }
        
        pos = Position(test_positions[test_case]);
        std::cout << "Testing position " << test_case << ": " << test_positions[test_case] << std::endl;
        
        int max_depth = 6; // Default search depth
        if (argc > 2) {
            max_depth = std::max(1, std::atoi(argv[2]));
        }
        
        auto search_globals = SearchGlobals::new_search_globals();
        
        auto start_time = std::chrono::high_resolution_clock::now();
        
        // Run the hybrid search
        auto best_move = best_move_search(pos, search_globals, max_depth);
        
        auto end_time = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
        
        std::cout << "----------------------------------------" << std::endl;
        if (best_move) {
            std::cout << "Best move: " << best_move->to_str() << std::endl;
        } else {
            std::cout << "No best move found" << std::endl;
        }
        
        std::cout << "Total search time: " << duration.count() << " ms" << std::endl;
        std::cout << "Total nodes searched: " << search_globals.nodes() << std::endl;
        
        if (duration.count() > 0) {
            uint64_t nps = search_globals.nodes() * 1000 / duration.count();
            std::cout << "Nodes per second: " << nps << std::endl;
        }
        
        std::cout << "Search completed successfully!" << std::endl;
        
    } else {
        // Worker processes run the worker loop
        mpi_worker_loop();
    }
    
    MPI_Finalize();
    return 0;
}