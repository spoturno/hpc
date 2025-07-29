#include <iostream>

#ifdef USE_MPI_SEARCH
#include <mpi.h>
#include <vector>
#endif

#include "libchess/Position.h"
#include "libchess/UCIService.h"

#include "search.h"
#include "tune.h"

using namespace libchess;

int main(int argc, char* argv[]) {
#ifdef USE_MPI_SEARCH
    MPI_Init(&argc, &argv);
    
    int rank;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    
    // Only rank 0 handles UCI communication
    if (rank != 0) {
        // Worker processes run the MPI worker loop
        search::mpi_worker_loop();
        MPI_Finalize();
        return 0;
    }
#endif

    std::ios_base::sync_with_stdio(false);
    std::cout.setf(std::ios::unitbuf);

    Position position{constants::STARTPOS_FEN};
    search::SearchGlobals search_globals = search::SearchGlobals::new_search_globals();
    auto position_handler = [&position](const UCIPositionParameters& position_parameters) {
        position = Position{position_parameters.fen()};
        if (!position_parameters.move_list()) {
            return;
        }
        for (auto& move_str : position_parameters.move_list()->move_list()) {
            position.make_move(*Move::from(move_str));
        }
    };
    auto go_handler = [&position, &search_globals](const UCIGoParameters& go_parameters) {
        search_globals.set_go_parameters(go_parameters);
        int depth = go_parameters.depth() ? *go_parameters.depth() : search::MAX_PLY;
        auto best_move = search::best_move_search(position, search_globals, depth);
        if (best_move) {
            UCIService::bestmove(best_move->to_str());
        } else {
            UCIService::bestmove("0000");
        }
    };
    auto stop_handler = [&search_globals]() { search_globals.set_stop_flag(true); };
    auto display_handler = [&position](const std::istringstream&) { position.display(); };

    UCIService uci_service{"LibchessEngine", "Manik Charan"};
    uci_service.register_position_handler(position_handler);
    uci_service.register_go_handler(go_handler);
    uci_service.register_stop_handler(stop_handler);
    uci_service.register_handler("d", display_handler, false);
    uci_service.register_handler("tune", tune_handler, false);

    std::string line;
    while (true) {
        std::getline(std::cin, line);
        if (line == "uci") {
            uci_service.run();
            break;
        } else {
            std::cout << "Supported Protocols: uci\n";
        }
    }

#ifdef USE_MPI_SEARCH
    MPI_Finalize();
#endif

    return 0;
}
