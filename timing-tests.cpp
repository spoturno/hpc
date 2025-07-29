#include <iostream>
#include <chrono>
#include <vector>
#include "libchess/Position.h"
#include "search.h"
#include "libchess/UCIService.h"

using namespace libchess;
using namespace search;

struct TestPosition {
    std::string fen;
    int depth;
};

int TEST_DEPTH = 3;

int main() {
    std::vector<TestPosition> positions = {
        {"r6r/1b2k1bq/8/8/7B/8/8/R3K2R b KQ - 3 2", 6},
        // {"8/8/8/2k5/2pP4/8/B7/4K3 b - d3 0 3", 6},
        {"r1bqkbnr/pppppppp/n7/8/8/P7/1PPPPPPP/RNBQKBNR w KQkq - 2 2", 6},
        {"r3k2r/p1pp1pb1/bn2Qnp1/2qPN3/1p2P3/2N5/PPPBBPPP/R3K2R b KQkq - 3 2", 6},
        {"2kr3r/p1ppqpb1/bn2Qnp1/3PN3/1p2P3/2N5/PPPBBPPP/R3K2R b KQ - 3 2", 6},
        {"rnb2k1r/pp1Pbppp/2p5/q7/2B5/8/PPPQNnPP/RNB1K2R w KQ - 3 9", 6},
        {"2r5/3pk3/8/2P5/8/2K5/8/8 w - - 5 4", 6},
        {"rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 6},
        {"r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", 6},
        
        {"r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 6},
        {"2rq1rk1/1p3pbp/p1npbnp1/4p3/4P3/1NN1BP2/PPPQ2PP/2KR1B1R w - - 0 1", 6},
        {"r1bq1rk1/1pp1bppp/p1np1n2/4p3/4P3/2N1B3/PPP1BPPP/R2Q1RK1 w - - 0 1", 6},
        // {"8/2p5/1p1p4/p2Pp3/P3Pp2/1P3Pp1/2P3Pp/6K1 w - - 0 1", 6},
        {"r1bq1r2/pppn1pbk/3p2np/3Pp1p1/2P1P3/2N2N1P/PP2BPP1/R1BQ1RK1 w - - 0 1", 6},
        {"r2q1rk1/pp2bppp/2n1p3/3pP3/3P1P2/2N5/PPPQ2PP/R3KB1R w KQ - 0 1", 6},
        {"r1bqk2r/1p2bppp/p1nppn2/8/3NP3/2N1B3/PPPQ1PPP/2KR1B1R w kq - 0 1", 6},
        {"r1bq1k1r/pp1n1ppp/2pb4/3p4/3P1B2/2NBPN2/PPP3PP/R2Q1RK1 w - - 0 1", 6},
        {"r4rk1/ppqb1ppp/2nbpn2/3p4/3P1B2/2NBPN2/PPPQ2PP/R4RK1 w - - 0 1", 6},
        {"6k1/5ppp/8/8/2B5/2P5/PP3PPP/6K1 w - - 0 1", 6},
        {"rnbq1k1r/pp3ppp/4pn2/2bp4/3P1B2/2N1PN2/PPPQ1PPP/R3KB1R w KQ - 0 1", 6},
        {"r4rk1/1bqnbppp/pp1ppn2/8/2PNPP2/1PN1B3/PB3QPP/R4RK1 w - - 0 1", 6},
        {"2r2rk1/1bqnbppp/pp1ppn2/8/2PNP3/1PN1BP2/PB3QPP/R4RK1 w - - 0 1", 6},
        {"2r5/1bqnbppk/pp1ppn1p/8/2PNP3/1PN1BP2/PB3QPP/R4RK1 w - - 0 1", 6},
        {"r1bq1rk1/pp3pbp/n2ppnp1/2p5/4PP2/2NPBN2/PPPQB1PP/R4RK1 w - - 0 1", 6}
    };


    for (const auto& test : positions) {
        Position pos = Position(test.fen);
        SearchGlobals globals = SearchGlobals::new_search_globals();
        std::cout << "FEN: " << test.fen << std::endl;

        // using same depth for all inputs
        // SearchResult result = search::search(pos, TEST_DEPTH); 

        // use custom depths
        // SearchResult result = search::search(pos, test.depth); 

        auto best_move = search::best_move_search(pos, globals, TEST_DEPTH); // Use best_move_search to get the best move


        std::cout << "Best Move: ";
        if (best_move) {
            std::cout << best_move->to_str();
        } else {
            std::cout << "N/A";
        }
        std::cout <<  std::endl;
        std::cout << "Score: " << "N/A" << std::endl;
        std::cout << "_____________________________" << std::endl;
        // if (best_move.has_value()) {
        //     std::cout << best_move.value();  // Check how to access moves if this is incorrect
        // } else {
        //     std::cout << "N/A";
        // }

    }

    return 0;
}
