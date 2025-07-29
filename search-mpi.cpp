#include <chrono>
#include <mpi.h>
#include <vector>
#include <algorithm>

#include "evaluation.h"
#include "search.h"

using namespace libchess;
using namespace eval;

// Simple Transposition Table
struct TTEntry {
    uint64_t hash;
    int depth;
    int score;
    uint16_t best_move;
    enum Flag { EXACT, LOWER_BOUND, UPPER_BOUND } flag;
    
    TTEntry() : hash(0), depth(-1), score(0), best_move(0), flag(EXACT) {}
};

class TranspositionTable {
private:
    static const size_t TABLE_SIZE = 1 << 20; // 1M entries (~32MB)
    std::vector<TTEntry> table;
    
public:
    TranspositionTable() : table(TABLE_SIZE) {}
    
    void store(uint64_t hash, int depth, int score, Move best_move, TTEntry::Flag flag) {
        size_t index = hash % TABLE_SIZE;
        TTEntry& entry = table[index];
        
        // Replace if deeper or same position
        if (entry.hash != hash || depth >= entry.depth) {
            entry.hash = hash;
            entry.depth = depth;
            entry.score = score;
            entry.best_move = best_move.value();
            entry.flag = flag;
        }
    }
    
    TTEntry* probe(uint64_t hash) {
        size_t index = hash % TABLE_SIZE;
        TTEntry& entry = table[index];
        return (entry.hash == hash) ? &entry : nullptr;
    }
    
    void clear() {
        std::fill(table.begin(), table.end(), TTEntry());
    }
};

// Global TT instance
TranspositionTable tt;

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

struct MPIWorkItem {
    uint16_t move_value;
    int depth;
    int alpha;
    int beta;
};

struct MPIResult {
    uint16_t move_value;
    int score;
    uint64_t nodes_searched; // Add node count
    bool has_pv;
    std::vector<uint16_t> pv_moves;
};

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
    uint64_t pos_hash = pos.hash();
    
    // Transposition Table probe
    Move tt_move;
    TTEntry* tt_entry = tt.probe(pos_hash);
    if (tt_entry && tt_entry->depth >= depth) {
        int tt_score = tt_entry->score;
        
        // Adjust mate scores
        if (tt_score >= MAX_MATE_SCORE) {
            tt_score -= ss->ply;
        } else if (tt_score <= -MAX_MATE_SCORE) {
            tt_score += ss->ply;
        }
        
        if ((tt_entry->flag == TTEntry::EXACT) ||
            (tt_entry->flag == TTEntry::LOWER_BOUND && tt_score >= beta) ||
            (tt_entry->flag == TTEntry::UPPER_BOUND && tt_score <= alpha)) {
            
            MoveList pv;
            if (tt_entry->best_move != 0) {
                pv.add(Move(tt_entry->best_move));
            }
            return {tt_score, pv};
        }
    }
    
    if (tt_entry && tt_entry->best_move != 0) {
        tt_move = Move(tt_entry->best_move);
    }

    sg.increment_nodes();

    MoveList pv;
    int best_score = -INFINITE;
    auto move_list = pos.legal_move_list();

    if (move_list.empty()) {
        return {pos.in_check() ? -MATE_SCORE + ss->ply : 0, {}};
    }

    // Null Move Pruning - skip our turn to see if position is still good
    if (!pv_node && !pos.in_check() && depth >= 3 && ss->ply > 0) {
        int static_eval = evaluate(pos);
        if (static_eval >= beta) {
            // Make null move (skip turn)
            pos.make_null_move();
            int null_reduction = 3;
            SearchResult null_result = -search_impl(pos, -beta, -beta + 1, depth - null_reduction - 1, ss + 1, sg);
            pos.unmake_move();
            
            if (null_result.score >= beta) {
                return {beta, {}};  // Null move cutoff
            }
        }
    }

    sort_moves(pos, move_list, ss, tt_move);

    int move_num = 0;
    Move best_move;

    for (auto move : move_list) {
        ++move_num;
        
        // Check if this move captures a piece (for LMR conditions)
        auto to_pt = pos.piece_type_on(move.to_square());

        pos.make_move(move);
        
        int new_depth = depth - 1;
        
        // Late Move Reductions (LMR) - reduce search depth for later moves
        if (move_num > 3 && depth > 2 && !pos.in_check() && !to_pt && move.type() != Move::Type::PROMOTION) {
            new_depth = std::max(1, depth - 2);
        }
        
        SearchResult search_result =
            move_num == 1 ? -search_impl(pos, -beta, -alpha, new_depth, ss + 1, sg)
                          : -search_impl(pos, -alpha - 1, -alpha, new_depth, ss + 1, sg);
        
        // Re-search with full depth if LMR gave a good score
        if (move_num > 1 && search_result.score > alpha) {
            if (new_depth < depth - 1) {
                // Re-search with full depth after LMR
                search_result = -search_impl(pos, -alpha - 1, -alpha, depth - 1, ss + 1, sg);
            }
            if (search_result.score > alpha) {
                search_result = -search_impl(pos, -beta, -alpha, depth - 1, ss + 1, sg);
            }
        }
        pos.unmake_move();

        if (ss->ply && sg.stop()) {
            return {0, {}};
        }

        if (search_result.score > best_score) {
            best_score = search_result.score;
            best_move = move;
            
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
                    // Store beta cutoff in TT
                    tt.store(pos_hash, depth, best_score, best_move, TTEntry::LOWER_BOUND);
                    break;
                }
            }
        }
    }
    
    // Store result in transposition table
    TTEntry::Flag flag = (best_score <= alpha) ? TTEntry::UPPER_BOUND : TTEntry::EXACT;
    if (best_move.value() != 0) {  // Only store if we have a best move
        int store_score = best_score;
        // Adjust mate scores for storage
        if (store_score >= MAX_MATE_SCORE) {
            store_score += ss->ply;
        } else if (store_score <= -MAX_MATE_SCORE) {
            store_score -= ss->ply;
        }
        tt.store(pos_hash, depth, store_score, best_move, flag);
    }
    
    return {best_score, pv};
}

int qsearch(Position& pos) {
    auto search_stack = SearchStack::new_search_stack();
    auto search_globals = SearchGlobals::new_search_globals();
    return qsearch_impl(pos, -INFINITE, +INFINITE, search_stack.begin(), search_globals);
}

// MPI-based root splitting search
SearchResult search(Position& pos, int depth) {
    auto search_globals = SearchGlobals::new_search_globals();
    return search(pos, search_globals, depth);
}

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
            // Broadcast empty result to all workers
            for (int worker = 1; worker < size; ++worker) {
                int stop_signal = -1;
                MPI_Send(&stop_signal, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
            }
            return empty_result;
        }

        // If only one process, fall back to sequential search
        if (size == 1) {
            return search_impl(pos, -INFINITE, +INFINITE, depth, search_stack.begin(), search_globals);
        }

        SearchResult best_result = {-INFINITE, {}};
        std::vector<bool> worker_busy(size, false);
        std::vector<Move> worker_moves(size);
        
        int move_idx = 0;
        int completed_moves = 0;
        int total_moves = moves.size();

        // Send initial work to all workers
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
                // No more moves, send "no work" signal
                int no_work_signal = 0;
                MPI_Send(&no_work_signal, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
                worker_busy[worker] = false;
            }
        }

        // Collect results and send more work
        while (completed_moves < total_moves) {
            MPI_Status status;
            int result_score;
            MPI_Recv(&result_score, 1, MPI_INT, MPI_ANY_SOURCE, 1, MPI_COMM_WORLD, &status);
            
            int worker = status.MPI_SOURCE;
            Move completed_move = worker_moves[worker];
            
            // Receive node count from worker
            uint64_t worker_nodes;
            MPI_Recv(&worker_nodes, 1, MPI_UNSIGNED_LONG_LONG, worker, 1, MPI_COMM_WORLD, &status);
            
            // Aggregate node count in search_globals
            for (uint64_t i = 0; i < worker_nodes; ++i) {
                search_globals.increment_nodes();
            }
            
            // Receive PV length
            int pv_length;
            MPI_Recv(&pv_length, 1, MPI_INT, worker, 1, MPI_COMM_WORLD, &status);
            
            SearchResult worker_result;
            worker_result.score = -result_score; // Negate because we're at root
            
            if (pv_length > 0) {
                // Receive PV moves
                std::vector<uint16_t> pv_values(pv_length);
                MPI_Recv(pv_values.data(), pv_length, MPI_UNSIGNED_SHORT, worker, 1, MPI_COMM_WORLD, &status);
                
                // Convert to MoveList
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
                // No more work for this depth, send "no work" signal
                int no_work_signal = 0;
                MPI_Send(&no_work_signal, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
            }
        }

        // Don't send stop signals here - workers will be reused for next depth
        return best_result;
    } else {
        // Workers should not call this function directly
        // They are handled through best_move_search
        return {0, {}};
    }
}

// Alternative implementation with non-blocking receives (more efficient)
// This could replace the current implementation for better performance
SearchResult search_nonblocking(Position& pos, SearchGlobals& search_globals, int depth) {
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    auto search_stack = SearchStack::new_search_stack();

    if (rank == 0) {
        // Master process with non-blocking receives
        MoveList moves = pos.legal_move_list();
        sort_moves(pos, moves, search_stack.begin());

        if (moves.empty()) {
            SearchResult empty_result = {pos.in_check() ? -MATE_SCORE : 0, {}};
            for (int worker = 1; worker < size; ++worker) {
                int stop_signal = -1;
                MPI_Send(&stop_signal, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
            }
            return empty_result;
        }

        if (size == 1) {
            return search_impl(pos, -INFINITE, +INFINITE, depth, search_stack.begin(), search_globals);
        }

        SearchResult best_result = {-INFINITE, {}};
        std::vector<MPI_Request> requests(size - 1);
        std::vector<int> worker_scores(size);
        std::vector<bool> worker_busy(size, false);
        std::vector<Move> worker_moves(size);
        
        int move_idx = 0;
        int completed_moves = 0;
        int total_moves = moves.size();

        // Send initial work using non-blocking sends
        for (int worker = 1; worker < size; ++worker) {
            if (move_idx < total_moves) {
                Move move = *(moves.begin() + move_idx);
                Position worker_pos = pos;
                worker_pos.make_move(move);
                
                std::string fen = worker_pos.fen();
                int fen_size = fen.size();
                MPI_Send(&fen_size, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
                MPI_Send(fen.c_str(), fen_size, MPI_CHAR, worker, 0, MPI_COMM_WORLD);
                MPI_Send(&depth, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
                
                // Post non-blocking receive for result
                MPI_Irecv(&worker_scores[worker], 1, MPI_INT, worker, 1, MPI_COMM_WORLD, &requests[worker - 1]);
                
                worker_busy[worker] = true;
                worker_moves[worker] = move;
                move_idx++;
            }
        }

        // Use MPI_Testany to check for completed workers
        while (completed_moves < total_moves) {
            int completed_worker_idx;
            int flag;
            MPI_Status status;
            
            MPI_Testany(size - 1, requests.data(), &completed_worker_idx, &flag, &status);
            
                         if (flag) {
                 int worker = completed_worker_idx + 1;
                 // Move completed_move = worker_moves[worker];  // TODO: Use this for result processing
                 
                 // Continue with rest of result collection...
                 // (Similar to current implementation but more efficient)
                
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
                    
                    MPI_Irecv(&worker_scores[worker], 1, MPI_INT, worker, 1, MPI_COMM_WORLD, &requests[worker - 1]);
                    
                    worker_busy[worker] = true;
                    worker_moves[worker] = move;
                    move_idx++;
                }
            }
        }

        return best_result;
    }
    
    return {0, {}};
}

std::optional<Move> best_move_search(Position& pos, SearchGlobals& search_globals, int max_depth) {
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    std::optional<Move> best_move;
    
    if (rank == 0) {
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
        // After iterative deepening is complete, send terminate signals to all workers
        for (int worker = 1; worker < size; ++worker) {
            int terminate_signal = -1;
            MPI_Send(&terminate_signal, 1, MPI_INT, worker, 0, MPI_COMM_WORLD);
        }
    } else {
        // Workers are handled in main.cpp
        // This should never be called for worker processes
    }

    return best_move;
}

void mpi_worker_loop() {
    SearchGlobals search_globals = SearchGlobals::new_search_globals();
    auto search_stack = SearchStack::new_search_stack();
    
    while (true) {
        // Receive work or stop signal
        int fen_size;
        MPI_Status status;
        MPI_Recv(&fen_size, 1, MPI_INT, 0, 0, MPI_COMM_WORLD, &status);
        
        if (fen_size == -1) {
            // Terminate signal - exit completely
            break;
        } else if (fen_size == 0) {
            // No work signal - continue to next iteration
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

        // Create position and search
        Position worker_pos(fen);
        
        // Reset worker's node count before search
        uint64_t initial_nodes = search_globals.nodes();
        auto result = search_impl(worker_pos, -INFINITE, INFINITE, search_depth - 1, 
                                search_stack.begin() + 1, search_globals);
        uint64_t nodes_searched = search_globals.nodes() - initial_nodes;

        // Send result back
        MPI_Send(&result.score, 1, MPI_INT, 0, 1, MPI_COMM_WORLD);
        
        // Send node count
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

// More efficient position serialization
struct SerializedPosition {
    uint64_t bitboards[16];  // All piece bitboards
    uint8_t castling_rights;
    uint8_t side_to_move;
    uint8_t en_passant_file;  // 255 if none
    uint16_t halfmove_clock;
    uint16_t fullmove_number;
    
    static SerializedPosition from_position(const Position& pos) {
        SerializedPosition sp;
        // This would need to be implemented based on Position's internal structure
        // For now, keeping FEN approach but marking for future optimization
        return sp;
    }
    
    Position to_position() const {
        // This would need to be implemented based on Position's internal structure
        // For now, keeping FEN approach but marking for future optimization
        return Position{constants::STARTPOS_FEN};
    }
};

} // namespace search 