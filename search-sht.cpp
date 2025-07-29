#include <chrono>
#include "evaluation.h"
#include "search.h"
#include "tt.h" // Re-enable the transposition table

#include <omp.h>

using namespace libchess;
using namespace eval;

namespace search {

// SearchStack implementation
std::array<SearchStack, MAX_PLY> SearchStack::new_search_stack() noexcept {
    std::array<SearchStack, MAX_PLY> search_stack{};
    for (unsigned i = 0; i < search_stack.size(); ++i) {
        auto& ss = search_stack[i];
        ss.ply = int(i);
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




    search::SearchResult search_impl(libchess::Position& pos, int alpha, int beta, int depth, search::SearchStack* ss, search::SearchGlobals& sg) {
        if (depth <= 0) {
            return {qsearch_impl(pos, alpha, beta, ss, sg), libchess::MoveList()};
        }

        if (ss->ply) {
            if (sg.stop()) {
                return {0, libchess::MoveList()};
            }
            if (pos.halfmoves() >= 100 || pos.is_repeat()) {
                return {0, libchess::MoveList()};
            }
            if (ss->ply >= search::MAX_PLY) {
                return {evaluate(pos), libchess::MoveList()};
            }

            alpha = std::max((-search::MATE_SCORE + ss->ply), alpha);
            beta = std::min((search::MATE_SCORE - ss->ply), beta);
            if (alpha >= beta) {
                return {alpha, libchess::MoveList()};
            }
        }

        bool pv_node = alpha != beta - 1;
        auto hash = pos.hash();
        TTEntry tt_entry = tt.probe(hash);
        std::optional<libchess::Move> tt_move;
        if (tt_entry.get_key() == hash) {
            tt_move = libchess::Move{tt_entry.get_move()};
            int tt_score = tt_entry.get_score();
            int tt_flag = tt_entry.get_flag();
            if (!pv_node && tt_entry.get_depth() >= depth) {
                if (tt_flag == TTConstants::FLAG_EXACT ||
                    (tt_flag == TTConstants::FLAG_LOWER && tt_score >= beta) ||
                    (tt_flag == TTConstants::FLAG_UPPER && tt_score <= alpha)) {
                    return {tt_score, libchess::MoveList()};
                }
            }
        }

        sg.increment_nodes();
        libchess::MoveList pv;
        int best_score = -INFINITE;
        auto move_list = pos.legal_move_list();
        if (move_list.empty()) {
            return {pos.in_check() ? -search::MATE_SCORE + ss->ply : 0, libchess::MoveList()};
        }

        sort_moves(pos, move_list, ss, tt_move);

        #pragma omp parallel
        {
            bool local_stop_search = false;
            #pragma omp for nowait
            for (int i = 0; i < move_list.size(); ++i) {
                if (local_stop_search) continue;

                auto move_it = std::next(move_list.begin(), i);
                auto move = *move_it;

                Position thread_pos = pos;
                thread_pos.make_move(move);  // Critical fix: actually make the move!
                SearchResult search_result =
                    i == 0 ? -search_impl(thread_pos, -beta, -alpha, depth - 1, ss + 1, sg)
                           : -search_impl(thread_pos, -alpha - 1, -alpha, depth - 1, ss + 1, sg);
                if (i > 0 && search_result.score > alpha) {
                    search_result = -search_impl(thread_pos, -beta, -alpha, depth - 1, ss + 1, sg);
                }
                thread_pos.unmake_move();  // Clean up

                #pragma omp critical
                {
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
                                local_stop_search = true;
                            }
                        }
                    }
                }
            }
        }

        int tt_flag = best_score >= beta ? TTConstants::FLAG_LOWER
                                         : best_score < alpha ? TTConstants::FLAG_UPPER : TTConstants::FLAG_EXACT;
        tt.write(tt_move ? tt_move->value() : 0, tt_flag, depth, best_score, hash);
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

    // SearchResult search(Position& pos, int depth) {
    //     tt.clear();
    //     auto search_stack = SearchStack::new_search_stack();
    //     auto search_globals = SearchGlobals::new_search_globals();
    //     int alpha = -INFINITE;
    //     int beta = +INFINITE;
    //     auto start = std::chrono::high_resolution_clock::now();
    //     SearchResult search_result =
    //         search_impl(pos, alpha, beta, depth, search_stack.begin(), search_globals);
    //     auto end = std::chrono::high_resolution_clock::now();
    //     auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

    //     std::uint64_t nodes = search_globals.nodes();
    //     std::uint64_t nps = duration ? nodes * 1000 / duration : nodes;
    //     std::cout << "Duration: " << duration << " ms" << std::endl;
    //     std::cout << "nodes: " << nodes << std::endl;
    //     std::cout << "nps: " << nps << std::endl;
    //     return search_result;
    // }

    SearchResult search(Position& pos, int depth) {
        // Note: For shared hash table approach, TT should not be cleared here
        // to allow sharing across depths within the same search
        auto search_stack = SearchStack::new_search_stack();
        auto search_globals = SearchGlobals::new_search_globals();
        int alpha = -INFINITE;
        int beta = +INFINITE;
        SearchResult search_result = search_impl(pos, alpha, beta, depth, search_stack.begin(), search_globals);
        return search_result;
    }

    std::optional<libchess::Move> best_move_search(libchess::Position& pos, SearchGlobals& search_globals, int max_depth) {
        std::optional<libchess::Move> best_move;
        tt.clear();  // Clear TT for new position, but keep it shared across depths within this search
        auto start_time = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::high_resolution_clock::now().time_since_epoch());  // Using curr_time() defined in search.h
        search_globals.set_stop_flag(false);
        search_globals.set_side_to_move(pos.side_to_move());
        search_globals.reset_nodes();
        search_globals.set_start_time(start_time);

        auto search_stack = SearchStack::new_search_stack();
        
        for (int depth = 1; depth <= max_depth; ++depth) {
            // Call search_impl directly with the correct SearchGlobals
            auto search_result = search_impl(pos, -INFINITE, +INFINITE, depth, search_stack.begin(), search_globals);

            if (depth > 1 && search_globals.stop()) {
                return best_move;
            }

            auto time_diff = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::high_resolution_clock::now().time_since_epoch()) - start_time;

            int score = search_result.score;
            auto& pv = search_result.pv;
            // if (!pv || pv->empty()) {
            //     break;
            // }

            if (pv && !pv->empty()) {
                best_move = *(pv->begin());
            }

            libchess::UCIScore uci_score = (score <= -MAX_MATE_SCORE) ?
                libchess::UCIScore((-score - MATE_SCORE) / 2, libchess::UCIScore::ScoreType::MATE) :
                (score >= MAX_MATE_SCORE) ?
                libchess::UCIScore((-score + MATE_SCORE + 1) / 2, libchess::UCIScore::ScoreType::MATE) :
                libchess::UCIScore(score, libchess::UCIScore::ScoreType::CENTIPAWNS);

            std::uint64_t time_taken = time_diff.count();
            std::uint64_t nodes = search_globals.nodes();
            std::uint64_t nps = time_taken ? nodes * 1000 / time_taken : nodes;

            std::unordered_map<std::string, std::any> info_values;
            info_values["depth"] = depth;
            info_values["score"] = uci_score;
            info_values["time"] = static_cast<int>(time_taken);
            info_values["nps"] = nps;
            info_values["nodes"] = nodes;

            std::vector<std::string> str_move_list;
            for (const auto& move : *pv) {
                str_move_list.push_back(move.to_str());
            }
            info_values["pv"] = libchess::UCIMoveList{str_move_list};

            libchess::UCIService::info(libchess::UCIInfoParameters(info_values));
        }

        return best_move;
    }


} // namespace search