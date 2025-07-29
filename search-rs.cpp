#include <chrono>

#include "evaluation.h"
#include "search.h"
#include "omp.h"

// #include "tt.h" // Commenting out TT

using namespace libchess;
using namespace eval;

namespace search {

// SearchStack implementation
std::array<SearchStack, MAX_PLY> SearchStack::new_search_stack() noexcept {
    std::array<SearchStack, MAX_PLY> search_stack{};
    for (unsigned i = 0; i < search_stack.size(); ++i) {
        auto& ss = search_stack[i];
        ss.ply = int(i);
        // ss.killer_moves = {{std::nullopt, std::nullopt}}; // Commenting out Killer Move
    }
    return search_stack;
}

void sort_moves(const Position& pos, MoveList& move_list, SearchStack* ss,
                std::optional<Move> tt_move = {}) {
    move_list.sort([&](Move move) {
        auto from_pt = *pos.piece_type_on(move.from_square());
        auto to_pt = pos.piece_type_on(move.to_square());

        int pawn_value = eval::MATERIAL[constants::PAWN][MIDGAME];
        int equality_bound = pawn_value - 50;
        if (tt_move && move == *tt_move) {
            return 20000;
        } else if (move.type() == Move::Type::ENPASSANT) {
            return 10000 + pawn_value + 20;
        } else if (to_pt) {
            int capture_value = eval::MATERIAL[*to_pt][MIDGAME] - eval::MATERIAL[from_pt][MIDGAME];
            if (capture_value >= equality_bound) {
                return 10000 + capture_value;
            } else {
                return 5000 + capture_value;
            }
        // } else if (ss->killer_moves[0] && move == *ss->killer_moves[0]) {
        //    return 7001;
        //} else if (ss->killer_moves[1] && move == *ss->killer_moves[1]) {
        //    return 7000;
        } else {
            return 0;
        }
    });
}

int qsearch_impl(Position& pos, int alpha, int beta, SearchStack* ss, SearchGlobals& sg) {
    if (sg.stop()) {
        return 0;
    }

    sg.increment_nodes();

    if (ss->ply >= MAX_PLY) {
        return evaluate(pos);
    }

    int eval = evaluate(pos);
    if (eval > alpha) {
        alpha = eval;
    }
    if (eval >= beta) {
        return beta;
    }

    MoveList move_list;
    if (pos.in_check()) {
        move_list = pos.check_evasion_move_list();

        if (move_list.empty()) {
            return pos.in_check() ? -MATE_SCORE + ss->ply : 0;
        }
    } else {
        pos.generate_capture_moves(move_list, pos.side_to_move());
        pos.generate_promotions(move_list, pos.side_to_move());
    }

    sort_moves(pos, move_list, ss);

    int best_score = -INFINITE;
    for (auto move : move_list) {
        if (!pos.is_legal_generated_move(move)) {
            continue;
        }
        pos.make_move(move);
        int score = -qsearch_impl(pos, -beta, -alpha, ss + 1, sg);
        pos.unmake_move();

        if (sg.stop()) {
            return 0;
        }

        if (score > best_score) {
            best_score = score;
            if (best_score > alpha) {
                alpha = best_score;
                if (alpha >= beta) {
                    break;
                }
            }
        }
    }

    return alpha;
}


SearchResult search_impl(Position& pos, int alpha, int beta, int depth, SearchStack* ss,
                         SearchGlobals& sg) {
    if (depth <= 0) {
        return {qsearch_impl(pos, alpha, beta, ss, sg), {}};
    }

    if (ss->ply) {
        if (sg.stop()) {
            return {0, {}};
        }

        if (pos.halfmoves() >= 100 || pos.is_repeat()) {
            return {0, {}};
        }

        if (ss->ply >= MAX_PLY) {
            return {evaluate(pos), {}};
        }

        alpha = std::max((-MATE_SCORE + ss->ply), alpha);
        beta = std::min((MATE_SCORE - ss->ply), beta);
        if (alpha >= beta) {
            return {alpha, {}};
        }
    }

    bool pv_node = alpha != beta - 1;

    sg.increment_nodes();

    MoveList pv;
    int best_score = -INFINITE;
    auto move_list = pos.legal_move_list();

    if (move_list.empty()) {
        return {pos.in_check() ? -MATE_SCORE + ss->ply : 0, {}};
    }

    sort_moves(pos, move_list, ss);

    int move_num = 0;

    for (auto move : move_list) {
        ++move_num;

        pos.make_move(move);
        SearchResult search_result =
            move_num == 1 ? -search_impl(pos, -beta, -alpha, depth - 1, ss + 1, sg)
                          : -search_impl(pos, -alpha - 1, -alpha, depth - 1, ss + 1, sg);
        if (move_num > 1 && search_result.score > alpha) {
            search_result = -search_impl(pos, -beta, -alpha, depth - 1, ss + 1, sg);
        }
        pos.unmake_move();

        if (ss->ply && sg.stop()) {
            return {0, {}};
        }

        if (search_result.score > best_score) {
            best_score = search_result.score;
            if (best_score > alpha) {
                alpha = best_score;

                if (pv_node) {
                    pv.clear();
                    pv.add(move);
                    if (search_result.pv) {
                        pv.add(*search_result.pv);
                    }
                }

                if (alpha >= beta) {
                    break;
                }
            }
        }
    }
    return {best_score, pv};
}


int qsearch(Position& pos) {
    auto search_stack = SearchStack::new_search_stack();
    auto search_globals = SearchGlobals::new_search_globals();
    return qsearch_impl(pos, -INFINITE, +INFINITE, search_stack.begin(), search_globals);
}

SearchResult search(Position& pos, SearchGlobals& sg, int depth) {
    auto search_stack = SearchStack::new_search_stack();
    int alpha = -INFINITE;
    int beta = +INFINITE;
    SearchResult search_result = search_impl(pos, alpha, beta, depth, search_stack.begin(), sg);
    return search_result;
}

SearchResult search(Position& pos, int depth) {
    auto search_stack = SearchStack::new_search_stack();
    auto search_globals = SearchGlobals::new_search_globals();

    MoveList moves = pos.legal_move_list();
    sort_moves(pos, moves, search_stack.begin());

    SearchResult best_result = {INFINITE, {}};
    omp_set_num_threads(8);

    #pragma omp parallel
    {
        SearchResult local_best = {INFINITE, {}};
        #pragma omp for schedule(dynamic)
        for (auto it = moves.begin(); it != moves.end(); ++it) {
            Position new_pos = pos;
            new_pos.make_move(*it);
            int local_alpha = -INFINITE;
            int local_beta = INFINITE;
            SearchResult result = search_impl(new_pos, local_alpha, local_beta, depth - 1, search_stack.begin() + 1, search_globals);
            result.score = -result.score;
            local_best.merge(result);
        }
        #pragma omp critical
        best_result.merge(local_best);
    }

    return best_result;
}

std::optional<Move> best_move_search(Position& pos, SearchGlobals& search_globals, int max_depth) {
    std::optional<Move> best_move;
    auto start_time = curr_time();
    search_globals.set_stop_flag(false);
    search_globals.set_side_to_move(pos.side_to_move());
    search_globals.reset_nodes();
    search_globals.set_start_time(start_time);
    for (int depth = 1; depth <= max_depth; ++depth) {
        auto search_result = search(pos, search_globals, depth);

        if (depth > 1 && search_globals.stop()) {
            return best_move;
        }

        auto time_diff = curr_time() - start_time;

        int score = search_result.score;
        auto& pv = search_result.pv;
        if (!pv) {
            break;
        }

        best_move = *pv->begin();

        UCIScore uci_score = [score]() {
            if (score <= -MAX_MATE_SCORE) {
                return UCIScore{(-score - MATE_SCORE) / 2, UCIScore::ScoreType::MATE};
            } else if (score >= MAX_MATE_SCORE) {
                return UCIScore{(-score + MATE_SCORE + 1) / 2, UCIScore::ScoreType::MATE};
            } else {
                return UCIScore{score, UCIScore::ScoreType::CENTIPAWNS};
            }
        }();



        std::uint64_t time_taken = time_diff.count();
        std::uint64_t nodes = search_globals.nodes();
        std::uint64_t nps = time_taken ? nodes * 1000 / time_taken : nodes;
        UCIInfoParameters info_parameters{{
            {"depth", depth},
            {"score", uci_score},
            {"time", int(time_taken)},
            {"nps", nps},
            {"nodes", nodes},
        }};

        std::vector<std::string> str_move_list;
        str_move_list.reserve(pv->size());
        for (auto move : *pv) {
            str_move_list.push_back(move.to_str());
        }
        info_parameters.set_pv(UCIMoveList{str_move_list});
        UCIService::info(info_parameters);
    }

    return best_move;
}

} // namespace search