#include <chrono>
#include <mpi.h>
#include <omp.h>
#include <vector>
#include <algorithm>

#include "evaluation.h"
#include "search.h"
#include "tt.h" // Use the existing transposition table

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

    auto hash = pos.hash();
    TTEntry tt_entry = tt.probe(hash);
    Move tt_move{0};
    if (tt_entry.get_key() == hash) {
        tt_move = Move{tt_entry.get_move()};
        int tt_score = tt_entry.get_score();
        int tt_flag = tt_entry.get_flag();
        if (!pv_node && tt_entry.get_depth() >= depth) {
            if (tt_flag == TTConstants::FLAG_EXACT ||
                (tt_flag == TTConstants::FLAG_LOWER && tt_score >= beta) ||
                (tt_flag == TTConstants::FLAG_UPPER && tt_score <= alpha)) {
                return {tt_score, {}};
            }
        }
    }

    sg.increment_nodes();

    MoveList pv;
    int best_score = -INFINITE;
    auto move_list = pos.legal_move_list();

    if (move_list.empty()) {
        return {pos.in_check() ? -MATE_SCORE + ss->ply : 0, {}};
    }

    sort_moves(pos, move_list, ss, tt_move);

    // Hybrid parallelization: Use OpenMP for parallel move search within this process
    // but only at certain depths to avoid thread overhead
    bool use_openmp = (depth >= 3 && ss->ply == 0 && move_list.size() >= 4);
    
    if (use_openmp) {
        // OpenMP parallel search for root or near-root nodes
        int shared_best_score = -INFINITE;
        MoveList shared_pv;
        bool cutoff_found = false;
        
        #pragma omp parallel
        {
            int local_best_score = -INFINITE;
            MoveList local_pv;
            int local_alpha = alpha;
            
            #pragma omp for schedule(dynamic, 1) nowait
            for (int i = 0; i < move_list.size(); ++i) {
                if (cutoff_found) continue;
                
                auto move_it = std::next(move_list.begin(), i);
                auto move = *move_it;
                
                Position thread_pos = pos;
                thread_pos.make_move(move);
                
                // Create thread-local search stack and use shared globals
                auto thread_stack = SearchStack::new_search_stack();
                
                SearchResult search_result =
                    i == 0 ? -search_impl(thread_pos, -beta, -local_alpha, depth - 1, thread_stack.begin() + 1, sg)
                           : -search_impl(thread_pos, -local_alpha - 1, -local_alpha, depth - 1, thread_stack.begin() + 1, sg);
                
                if (i > 0 && search_result.score > local_alpha) {
                    search_result = -search_impl(thread_pos, -beta, -local_alpha, depth - 1, thread_stack.begin() + 1, sg);
                }
                
                #pragma omp critical
                {
                    // Node counting is handled automatically since we share sg
                    
                    if (search_result.score > shared_best_score) {
                        shared_best_score = search_result.score;
                        if (shared_best_score > alpha) {
                            alpha = shared_best_score;
                            local_alpha = alpha; // Update local alpha for other threads
                            
                            if (pv_node) {
                                shared_pv.clear();
                                shared_pv.add(move);
                                if (search_result.pv) {
                                    shared_pv.add(*search_result.pv);
                                }
                            }
                            
                            if (alpha >= beta) {
                                cutoff_found = true;
                            }
                        }
                    }
                }
            }
        }
        
        best_score = shared_best_score;
        pv = shared_pv;
    } else {
        // Sequential search for deeper nodes or when OpenMP overhead isn't worth it
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
    }

    int tt_flag = best_score >= beta ? TTConstants::FLAG_LOWER
                                     : best_score < alpha ? TTConstants::FLAG_UPPER : TTConstants::FLAG_EXACT;
    if (!pv.empty()) {
        tt.write(pv.begin()->value(), tt_flag, depth, best_score, hash);
    }
    return {best_score, pv};
}

int qsearch(Position& pos) {
    auto search_stack = SearchStack::new_search_stack();
    auto search_globals = SearchGlobals::new_search_globals();
    return qsearch_impl(pos, -INFINITE, +INFINITE, search_stack.begin(), search_globals);
}

// MPI-based root splitting with OpenMP within each process
SearchResult search(Position& pos, SearchGlobals& search_globals, int depth) {
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    auto search_stack = SearchStack::new_search_stack();

    if (rank == 0) {
        // Master process
        MoveList moves = pos.legal_move_list();
        sort_moves(pos, moves, search_stack.begin());

        if (moves.empty()) {
            SearchResult empty_result = {pos.in_check() ? -MATE_SCORE : 0, {}};
            // Signal all workers to stop
            for (int worker = 1; worker < size; ++worker) {
                int stop_signal = -1;
                MPI_Send(&stop_signal, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
            }
            return empty_result;
        }

        // If only one process, use hybrid search directly
        if (size == 1) {
            return search_impl(pos, -INFINITE, +INFINITE, depth, search_stack.begin(), search_globals);
        }

        SearchResult best_result = {-INFINITE, {}};
        std::vector<bool> worker_busy(size, false);
        std::vector<Move> worker_moves(size);
        
        int move_idx = 0;
        int completed_moves = 0;
        int total_moves = moves.size();

        // Distribute initial work to all workers
        for (int worker = 1; worker < size; ++worker) {
            if (move_idx < total_moves) {
                Move move = *(moves.begin() + move_idx);
                Position worker_pos = pos;
                worker_pos.make_move(move);
                
                // Send position and search parameters
                std::string fen = worker_pos.fen();
                int fen_size = fen.size();
                MPI_Send(&fen_size, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
                MPI_Send(fen.c_str(), fen_size, MPI_CHAR, worker, 0, MPI_COMM_WORLD);
                MPI_Send(&depth, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
                
                worker_busy[worker] = true;
                worker_moves[worker] = move;
                move_idx++;
            } else {
                int no_work_signal = 0;
                MPI_Send(&no_work_signal, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
                worker_busy[worker] = false;
            }
        }

        // Collect results and redistribute work
        while (completed_moves < total_moves) {
            MPI_Status status;
            int result_score;
            MPI_Recv(&result_score, 1, MPI_INT, MPI_ANY_SOURCE, 1, MPI_COMM_WORLD, &status);
            
            int worker = status.MPI_SOURCE;
            Move completed_move = worker_moves[worker];
            
            // Receive node count
            uint64_t worker_nodes;
            MPI_Recv(&worker_nodes, 1, MPI_UNSIGNED_LONG_LONG, worker, 1, MPI_COMM_WORLD, &status);
            
            // Aggregate node count
            for (uint64_t i = 0; i < worker_nodes; ++i) {
                search_globals.increment_nodes();
            }
            
            // Receive PV length
            int pv_length;
            MPI_Recv(&pv_length, 1, MPI_INT, worker, 1, MPI_COMM_WORLD, &status);
            
            SearchResult worker_result;
            worker_result.score = -result_score; // Negate because we're at root
            
            if (pv_length > 0) {
                std::vector<uint16_t> pv_values(pv_length);
                MPI_Recv(pv_values.data(), pv_length, MPI_UNSIGNED_SHORT, worker, 1, MPI_COMM_WORLD, &status);
                
                MoveList pv;
                pv.add(completed_move);
                for (int i = 0; i < pv_length; ++i) {
                    pv.add(Move(pv_values[i]));
                }
                worker_result.pv = pv;
            } else {
                MoveList pv;
                pv.add(completed_move);
                worker_result.pv = pv;
            }

            // Update best result
            if (worker_result.score > best_result.score) {
                best_result = worker_result;
            }

            completed_moves++;
            worker_busy[worker] = false;

            // Send more work if available
            if (move_idx < total_moves) {
                Move move = *(moves.begin() + move_idx);
                Position worker_pos = pos;
                worker_pos.make_move(move);
                
                std::string fen = worker_pos.fen();
                int fen_size = fen.size();
                MPI_Send(&fen_size, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
                MPI_Send(fen.c_str(), fen_size, MPI_CHAR, worker, 0, MPI_COMM_WORLD);
                MPI_Send(&depth, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
                
                worker_busy[worker] = true;
                worker_moves[worker] = move;
                move_idx++;
            } else {
                int no_work_signal = 0;
                MPI_Send(&no_work_signal, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
            }
        }

        return best_result;
    } else {
        // Workers should not call this function directly
        return {0, {}};
    }
}

SearchResult search(Position& pos, int depth) {
    auto search_globals = SearchGlobals::new_search_globals();
    return search(pos, search_globals, depth);
}

std::optional<Move> best_move_search(Position& pos, SearchGlobals& search_globals, int max_depth) {
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    std::optional<Move> best_move;
    
    if (rank == 0) {
        // Master process handles iterative deepening
        auto start_time = curr_time();
        search_globals.set_stop_flag(false);
        search_globals.set_side_to_move(pos.side_to_move());
        search_globals.reset_nodes();
        search_globals.set_start_time(start_time);
        
        // Clear transposition table for clean search
        tt.clear();
        
        for (int depth = 1; depth <= max_depth; ++depth) {
            auto search_result = search(pos, search_globals, depth);

            if (depth > 1 && search_globals.stop()) {
                return best_move;
            }

            auto time_diff = curr_time() - start_time;

            int score = search_result.score;
            auto& pv = search_result.pv;
            if (!pv || pv->empty()) {
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
        
        // Signal all workers to terminate
        for (int worker = 1; worker < size; ++worker) {
            int terminate_signal = -1;
            MPI_Send(&terminate_signal, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
        }
    }

    return best_move;
}

void mpi_worker_loop() {
    SearchGlobals search_globals = SearchGlobals::new_search_globals();
    auto search_stack = SearchStack::new_search_stack();
    
    // Set number of OpenMP threads for each worker process
    int num_threads = omp_get_max_threads();
    // Use fewer threads per worker to avoid oversubscription
    omp_set_num_threads(std::max(1, num_threads / 2));
    
    while (true) {
        // Receive work or stop signal
        int fen_size;
        MPI_Status status;
        MPI_Recv(&fen_size, 1, MPI_INT, 0, 0, MPI_COMM_WORLD, &status);
        
        if (fen_size == -1) {
            // Terminate signal
            break;
        } else if (fen_size == 0) {
            // No work signal
            continue;
        }

        // Receive position FEN
        std::vector<char> fen_buffer(fen_size + 1);
        MPI_Recv(fen_buffer.data(), fen_size, MPI_CHAR, 0, 0, MPI_COMM_WORLD, &status);
        fen_buffer[fen_size] = '\0';
        std::string fen(fen_buffer.data());

        // Receive depth
        int search_depth;
        MPI_Recv(&search_depth, 1, MPI_INT, 0, 0, MPI_COMM_WORLD, &status);

        // Create position and search using hybrid approach
        Position worker_pos(fen);
        
        uint64_t initial_nodes = search_globals.nodes();
        auto result = search_impl(worker_pos, -INFINITE, INFINITE, search_depth - 1, 
                                search_stack.begin() + 1, search_globals);
        uint64_t nodes_searched = search_globals.nodes() - initial_nodes;

        // Send result back
        MPI_Send(&result.score, 1, MPI_INT, 0, 1, MPI_COMM_WORLD);
        MPI_Send(&nodes_searched, 1, MPI_UNSIGNED_LONG_LONG, 0, 1, MPI_COMM_WORLD);
        
        // Send PV
        int pv_length = result.pv ? result.pv->size() : 0;
        MPI_Send(&pv_length, 1, MPI_INT, 0, 1, MPI_COMM_WORLD);
        
        if (pv_length > 0) {
            std::vector<uint16_t> pv_values;
            for (auto move : *result.pv) {
                pv_values.push_back(move.value());
            }
            MPI_Send(pv_values.data(), pv_length, MPI_UNSIGNED_SHORT, 0, 1, MPI_COMM_WORLD);
        }
    }
}

} // namespace search