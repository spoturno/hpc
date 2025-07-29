#!/usr/bin/env python3
"""
Definitive Chess Engine Evaluation Script
Comprehensive performance analysis and comparison of all search algorithm implementations:
1. Sequential (old-search.cpp) - Single-threaded baseline
2. SharedHashTable (search-sht.cpp) - OpenMP with shared transposition table
3. RootSplitting (search-rs.cpp) - OpenMP with root splitting parallelization
4. MPI (search-mpi.cpp) - Distributed parallel search using MPI
5. Hybrid (search-hybrid.cpp) - Combined OpenMP+MPI approach

Metrics analyzed:
- NPS (Nodes Per Second)
- Parallelization efficiency 
- Speed-up ratios
- Computational efficiency
- Scalability analysis
- Load balancing effectiveness
"""

import os
import sys
import subprocess
import time
import json
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import argparse
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple, Optional
from concurrent.futures import ThreadPoolExecutor, as_completed
import warnings
warnings.filterwarnings('ignore')

class ChessEngineEvaluator:
    def __init__(self, output_dir="results"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)
        
        # Algorithm configurations
        self.algorithms = {
            'Sequential': {
                'file': 'old-search.cpp',
                'description': 'Single-threaded baseline implementation',
                'type': 'sequential',
                'build_cmd': ['make', 'clean', '&&', 'ln', '-sf', 'old-search.cpp', 'search.cpp', '&&', 'make', 'engine'],
                'run_cmd': './engine'
            },
            'SharedHashTable': {
                'file': 'search-sht.cpp', 
                'description': 'OpenMP parallel search with shared transposition table',
                'type': 'openmp',
                'build_cmd': ['make', 'clean', '&&', 'ln', '-sf', 'search-sht.cpp', 'search.cpp', '&&', 'make', 'engine'],
                'run_cmd': './engine'
            },
            'RootSplitting': {
                'file': 'search-rs.cpp',
                'description': 'OpenMP parallel search with root splitting',
                'type': 'openmp', 
                'build_cmd': ['make', 'clean', '&&', 'ln', '-sf', 'search-rs.cpp', 'search.cpp', '&&', 'make', 'engine'],
                'run_cmd': './engine'
            },
            'MPI': {
                'file': 'search-mpi.cpp',
                'description': 'Distributed parallel search using MPI',
                'type': 'mpi',
                'build_cmd': ['make', 'engine-mpi'],
                'run_cmd': 'mpirun'
            },
            'Hybrid': {
                'file': 'search-hybrid.cpp',
                'description': 'Combined OpenMP+MPI approach',
                'type': 'hybrid',
                'build_cmd': ['make', '-f', 'Makefile.hybrid', 'clean', '&&', 'make', '-f', 'Makefile.hybrid'],
                'run_cmd': 'mpirun'
            }
        }
        
        # Test configurations
        self.test_positions = [
            {
                'name': 'Starting Position',
                'fen': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
                'complexity': 'low'
            },
            {
                'name': 'Tactical Position', 
                'fen': 'r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 4 4',
                'complexity': 'medium'
            },
            {
                'name': 'Complex Middlegame',
                'fen': 'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
                'complexity': 'high'
            },
            {
                'name': 'Endgame Position',
                'fen': '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
                'complexity': 'medium'
            }
        ]
        
        self.depths = [3, 4, 5, 6, 7, 8]
        self.thread_counts = [1, 2, 4, 6, 8]
        self.process_counts = [1, 2, 4, 6, 8]
        
        self.results = []
        self.system_info = self._get_system_info()
        
    def _get_system_info(self) -> Dict:
        """Collect system information"""
        try:
            cpu_info = subprocess.run(['sysctl', '-n', 'machdep.cpu.brand_string'], 
                                    capture_output=True, text=True).stdout.strip()
        except:
            try:
                cpu_info = subprocess.run(['cat', '/proc/cpuinfo'], 
                                        capture_output=True, text=True).stdout
                cpu_info = [line for line in cpu_info.split('\n') if 'model name' in line][0].split(':')[1].strip()
            except:
                cpu_info = "Unknown"
        
        try:
            cpu_count = os.cpu_count()
        except:
            cpu_count = "Unknown"
            
        return {
            'timestamp': datetime.now().isoformat(),
            'cpu_info': cpu_info,
            'cpu_count': cpu_count,
            'os': os.uname().sysname,
            'os_version': os.uname().release,
            'architecture': os.uname().machine
        }
    
    def _check_dependencies(self) -> Dict[str, bool]:
        """Check which dependencies are available"""
        deps = {
            'mpi': False,
            'openmp': False,
            'make': False
        }
        
        # Check MPI
        try:
            subprocess.run(['mpirun', '--version'], capture_output=True, check=True)
            subprocess.run(['mpic++', '--version'], capture_output=True, check=True)
            deps['mpi'] = True
            print("✅ MPI detected")
        except:
            print("⚠️  MPI not available - MPI and Hybrid tests will be skipped")
        
        # Check Make
        try:
            subprocess.run(['make', '--version'], capture_output=True, check=True)
            deps['make'] = True
            print("✅ Make detected")
        except:
            print("❌ Make not available")
            return deps
        
        # Check OpenMP (basic test)
        try:
            test_code = '#include <omp.h>\nint main() { return omp_get_max_threads(); }'
            result = subprocess.run(['clang++', '-fopenmp', '-x', 'c++', '-', '-o', '/tmp/omp_test'],
                                  input=test_code, text=True, capture_output=True)
            if result.returncode == 0:
                deps['openmp'] = True
                os.remove('/tmp/omp_test')
                print("✅ OpenMP detected")
        except:
            print("⚠️  OpenMP detection failed")
        
        return deps
    
    def _build_algorithm(self, algorithm: str) -> bool:
        """Build a specific algorithm"""
        config = self.algorithms[algorithm]
        
        print(f"  Building {algorithm}...")
        
        try:
            if algorithm in ['MPI', 'Hybrid'] and not self.dependencies['mpi']:
                print(f"  ❌ Skipping {algorithm} - MPI not available")
                return False
                
            # Build command
            build_cmd = ' '.join(config['build_cmd'])
            result = subprocess.run(build_cmd, shell=True, capture_output=True, text=True)
            
            if result.returncode == 0:
                # Verify that the executable was actually created
                expected_executable = self._get_executable_path(algorithm)
                
                # Wait a bit for file system to sync
                import time
                time.sleep(0.5)
                
                if os.path.exists(expected_executable) and os.access(expected_executable, os.X_OK):
                    print(f"  ✅ {algorithm} built successfully")
                    return True
                else:
                    print(f"  ❌ {algorithm} build succeeded but executable not found: {expected_executable}")
                    return False
            else:
                print(f"  ❌ {algorithm} build failed: {result.stderr}")
                return False
                
        except Exception as e:
            print(f"  ❌ {algorithm} build error: {e}")
            return False
    
    def _get_executable_path(self, algorithm: str) -> str:
        """Get the expected executable path for an algorithm"""
        if algorithm == 'MPI':
            return './engine-mpi'
        elif algorithm == 'Hybrid':
            return './engine-hybrid'
        else:
            # For OpenMP algorithms (Sequential, SharedHashTable, RootSplitting)
            return './engine'
    
    def _ensure_algorithm_built(self, algorithm: str) -> bool:
        """Ensure that the correct algorithm implementation is built and ready to run"""
        config = self.algorithms[algorithm]
        
        try:
            # For OpenMP algorithms, we need to rebuild each time with the correct search implementation
            if algorithm in ['Sequential', 'SharedHashTable', 'RootSplitting']:
                build_cmd = ' '.join(config['build_cmd'])
                result = subprocess.run(build_cmd, shell=True, capture_output=True, text=True)
                
                if result.returncode != 0:
                    return False
                
                # Wait for filesystem sync and verify executable exists
                import time
                time.sleep(0.2)
                
                executable_path = self._get_executable_path(algorithm)
                return os.path.exists(executable_path) and os.access(executable_path, os.X_OK)
            
            # For MPI, we need to ensure it's built since clean commands might have removed it
            elif algorithm == 'MPI':
                executable_path = self._get_executable_path(algorithm)
                
                # Check if executable exists and is executable
                if not (os.path.exists(executable_path) and os.access(executable_path, os.X_OK)):
                    # Rebuild MPI engine
                    build_cmd = ' '.join(config['build_cmd'])
                    result = subprocess.run(build_cmd, shell=True, capture_output=True, text=True)
                    
                    if result.returncode != 0:
                        return False
                    
                    # Wait for filesystem sync
                    import time
                    time.sleep(0.5)
                
                return os.path.exists(executable_path) and os.access(executable_path, os.X_OK)
            
            # For Hybrid, they have their own dedicated executables
            return True
            
        except Exception:
            return False
    
    def _run_engine_test(self, algorithm: str, depth: int, threads: int, position_fen: str, timeout: int = 60) -> Optional[Dict]:
        """Run a single engine test"""
        config = self.algorithms[algorithm]
        
        # Prepare UCI commands
        uci_commands = f"uci\nposition fen {position_fen}\ngo depth {depth}\nquit\n"
        
        try:
            start_time = time.time()
            
            # Get the correct executable path and ensure it's built correctly for this algorithm
            executable_path = self._get_executable_path(algorithm)
            
            # For OpenMP and MPI algorithms, we need to ensure the correct implementation is built
            if algorithm in ['Sequential', 'SharedHashTable', 'RootSplitting', 'MPI']:
                if not self._ensure_algorithm_built(algorithm):
                    return {
                        'algorithm': algorithm, 'depth': depth, 'threads': threads,
                        'success': False, 'error': 'Build verification failed'
                    }
            
            if algorithm == 'Sequential':
                # Sequential - no threading
                cmd = [executable_path]
                env = os.environ.copy()
                
            elif config['type'] == 'openmp':
                # OpenMP algorithms
                cmd = [executable_path]
                env = os.environ.copy()
                env['OMP_NUM_THREADS'] = str(threads)
                
            elif algorithm == 'MPI':
                # Pure MPI
                cmd = ['mpirun', '-np', str(threads), executable_path]
                env = os.environ.copy()
                
            elif algorithm == 'Hybrid':
                # Hybrid OpenMP+MPI
                # Use fewer OpenMP threads per process for hybrid
                omp_threads = max(1, threads // 2)
                processes = max(1, threads // omp_threads)
                cmd = ['mpirun', '-np', str(processes), executable_path]
                env = os.environ.copy()
                env['OMP_NUM_THREADS'] = str(omp_threads)
            
            # Run the engine
            process = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, 
                                     stderr=subprocess.PIPE, text=True, env=env)
            
            stdout, stderr = process.communicate(input=uci_commands, timeout=timeout)
            wall_time = (time.time() - start_time) * 1000  # Convert to ms
            
            # Parse output
            result = self._parse_uci_output(stdout, wall_time)
            
            if result:
                result.update({
                    'algorithm': algorithm,
                    'depth': depth,
                    'threads': threads,
                    'wall_time_ms': wall_time,
                    'success': True
                })
                return result
            else:
                return {
                    'algorithm': algorithm, 'depth': depth, 'threads': threads,
                    'wall_time_ms': wall_time, 'success': False, 'error': 'Parse failed'
                }
                
        except subprocess.TimeoutExpired:
            return {
                'algorithm': algorithm, 'depth': depth, 'threads': threads,
                'success': False, 'error': 'Timeout'
            }
        except Exception as e:
            return {
                'algorithm': algorithm, 'depth': depth, 'threads': threads,
                'success': False, 'error': str(e)
            }
    
    def _parse_uci_output(self, output: str, wall_time: float) -> Optional[Dict]:
        """Parse UCI engine output"""
        lines = output.strip().split('\n')
        
        info_line = None
        best_move = None
        
        # Find the last info line and best move
        for line in lines:
            if line.startswith('info') and 'depth' in line:
                info_line = line
            elif line.startswith('bestmove'):
                best_move = line.split()[1] if len(line.split()) > 1 else None
        
        if not info_line:
            return None
        
        # Parse info line
        parts = info_line.split()
        result = {'best_move': best_move}
        
        i = 0
        while i < len(parts):
            if parts[i] == 'depth' and i + 1 < len(parts):
                result['depth'] = int(parts[i + 1])
                i += 2
            elif parts[i] == 'nodes' and i + 1 < len(parts):
                result['nodes'] = int(parts[i + 1])
                i += 2
            elif parts[i] == 'time' and i + 1 < len(parts):
                result['engine_time_ms'] = int(parts[i + 1])
                i += 2
            elif parts[i] == 'nps' and i + 1 < len(parts):
                result['nps'] = int(parts[i + 1])
                i += 2
            elif parts[i] == 'score' and i + 2 < len(parts):
                result['score_type'] = parts[i + 1]
                result['score_value'] = int(parts[i + 2])
                i += 3
            else:
                i += 1
        
        # Calculate NPS if not provided
        if 'nps' not in result and 'nodes' in result and 'engine_time_ms' in result and result['engine_time_ms'] > 0:
            result['nps'] = int(result['nodes'] * 1000 / result['engine_time_ms'])
        
        return result
    
    def run_comprehensive_evaluation(self, quick_mode: bool = False) -> str:
        """Run comprehensive evaluation of all algorithms"""
        print("🚀 Starting Comprehensive Chess Engine Evaluation")
        print("=" * 60)
        
        # Check dependencies
        print("\n🔍 Checking Dependencies...")
        self.dependencies = self._check_dependencies()
        
        if not self.dependencies['make']:
            print("❌ Make is required for building engines")
            return None
        
        # Filter algorithms based on dependencies
        available_algorithms = []
        for alg_name, config in self.algorithms.items():
            if alg_name in ['MPI', 'Hybrid'] and not self.dependencies['mpi']:
                continue
            available_algorithms.append(alg_name)
        
        print(f"\n📊 Testing Algorithms: {', '.join(available_algorithms)}")
        
        # Build all algorithms
        print("\n🔨 Building Algorithms...")
        built_algorithms = []
        for algorithm in available_algorithms:
            if self._build_algorithm(algorithm):
                built_algorithms.append(algorithm)
        
        if not built_algorithms:
            print("❌ No algorithms built successfully")
            return None
        
        print(f"\n✅ Successfully built: {', '.join(built_algorithms)}")
        
        # Configure test matrix
        if quick_mode:
            test_depths = [4, 6]
            test_positions = [self.test_positions[0]]  # Just starting position
            thread_configs = {
                'Sequential': [1],
                'SharedHashTable': [1, 4, 8],
                'RootSplitting': [1, 4, 8], 
                'MPI': [1, 4, 8],
                'Hybrid': [1, 4, 8]
            }
        else:
            test_depths = self.depths
            test_positions = self.test_positions
            thread_configs = {
                'Sequential': [1],
                'SharedHashTable': self.thread_counts,
                'RootSplitting': self.thread_counts,
                'MPI': self.process_counts,
                'Hybrid': self.thread_counts
            }
        
        # Run evaluation tests
        print(f"\n🧪 Running Evaluation Tests...")
        print(f"   Depths: {test_depths}")
        print(f"   Positions: {len(test_positions)}")
        
        total_tests = sum([
            len(test_depths) * len(test_positions) * len(thread_configs.get(alg, [1]))
            for alg in built_algorithms
        ])
        print(f"   Total tests: {total_tests}")
        
        test_count = 0
        for position in test_positions:
            print(f"\n📍 Testing position: {position['name']}")
            
            for algorithm in built_algorithms:
                threads_to_test = thread_configs.get(algorithm, [1])
                
                for depth in test_depths:
                    for threads in threads_to_test:
                        test_count += 1
                        print(f"  [{test_count:3d}/{total_tests}] {algorithm:15s} d={depth} t={threads:2d}", end=" ... ")
                        
                        result = self._run_engine_test(algorithm, depth, threads, position['fen'])
                        
                        if result and result.get('success'):
                            print(f"✅ {result.get('nps', 0):7,.0f} NPS")
                            result.update({
                                'position_name': position['name'],
                                'position_complexity': position['complexity'],
                                'position_fen': position['fen']
                            })
                            self.results.append(result)
                        else:
                            error = result.get('error', 'Unknown') if result else 'Failed'
                            print(f"❌ {error}")
        
        # Save results
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_file = self.output_dir / f"definitive_evaluation_{timestamp}.json"
        
        final_data = {
            'system_info': self.system_info,
            'test_configuration': {
                'algorithms_tested': built_algorithms,
                'depths': test_depths,
                'positions': [p['name'] for p in test_positions],
                'total_tests': total_tests,
                'successful_tests': len(self.results)
            },
            'results': self.results
        }
        
        with open(output_file, 'w') as f:
            json.dump(final_data, f, indent=2)
        
        print(f"\n💾 Results saved to: {output_file}")
        
        return str(output_file)
    
    def analyze_results(self, results_file: str = None) -> None:
        """Analyze and visualize results"""
        if results_file:
            with open(results_file, 'r') as f:
                data = json.load(f)
            self.results = data['results']
            self.system_info = data['system_info']
        
        if not self.results:
            print("❌ No results to analyze")
            return
        
        df = pd.DataFrame(self.results)
        
        print("\n📈 PERFORMANCE ANALYSIS")
        print("=" * 60)
        
        self._print_summary_statistics(df)
        self._analyze_parallel_efficiency(df)
        self._analyze_scalability(df)
        self._create_comprehensive_visualizations(df, results_file)
    
    def _print_summary_statistics(self, df: pd.DataFrame) -> None:
        """Print comprehensive summary statistics"""
        print(f"\n📊 Summary Statistics")
        print(f"   Total successful tests: {len(df)}")
        print(f"   Algorithms tested: {', '.join(df['algorithm'].unique())}")
        print(f"   Depth range: {df['depth'].min()}-{df['depth'].max()}")
        print(f"   Thread/Process range: {df['threads'].min()}-{df['threads'].max()}")
        
        print(f"\n⚡ Performance Ranges:")
        print(f"   Nodes: {df['nodes'].min():,} - {df['nodes'].max():,}")
        print(f"   Wall Time: {df['wall_time_ms'].min():.0f}ms - {df['wall_time_ms'].max():.0f}ms")
        print(f"   NPS: {df['nps'].min():,} - {df['nps'].max():,}")
        
        # Best performing configuration for each algorithm
        print(f"\n🏆 Peak Performance by Algorithm:")
        for algorithm in df['algorithm'].unique():
            algo_data = df[df['algorithm'] == algorithm]
            best_config = algo_data.loc[algo_data['nps'].idxmax()]
            print(f"   {algorithm:15s}: {best_config['nps']:8,.0f} NPS (d={best_config['depth']}, t={best_config['threads']})")
    
    def _analyze_parallel_efficiency(self, df: pd.DataFrame) -> None:
        """Analyze parallel efficiency and speedup"""
        print(f"\n🚀 Parallel Efficiency Analysis")
        print("-" * 40)
        
        # Get sequential baseline
        sequential_data = df[df['algorithm'] == 'Sequential']
        if sequential_data.empty:
            print("⚠️  No sequential baseline available for comparison")
            return
        
        parallel_algorithms = [alg for alg in df['algorithm'].unique() if alg != 'Sequential']
        
        for algorithm in parallel_algorithms:
            print(f"\n📊 {algorithm} Efficiency:")
            algo_data = df[df['algorithm'] == algorithm]
            
            print(f"{'Depth':<6} {'Threads':<8} {'Speedup':<8} {'Efficiency':<12} {'NPS Ratio':<10}")
            print("-" * 50)
            
            for depth in sorted(algo_data['depth'].unique()):
                # Get sequential baseline for this depth  
                seq_baseline = sequential_data[sequential_data['depth'] == depth]
                if seq_baseline.empty:
                    continue
                
                seq_time = seq_baseline['wall_time_ms'].iloc[0]
                seq_nps = seq_baseline['nps'].iloc[0]
                
                depth_data = algo_data[algo_data['depth'] == depth]
                for _, row in depth_data.iterrows():
                    speedup = seq_time / row['wall_time_ms'] if row['wall_time_ms'] > 0 else 0
                    efficiency = (speedup / row['threads']) * 100 if row['threads'] > 0 else 0
                    nps_ratio = row['nps'] / seq_nps if seq_nps > 0 else 0
                    
                    print(f"{depth:<6} {row['threads']:<8} {speedup:<8.2f} {efficiency:<12.1f}% {nps_ratio:<10.2f}")
    
    def _analyze_scalability(self, df: pd.DataFrame) -> None:
        """Analyze scalability characteristics"""
        print(f"\n📈 Scalability Analysis")
        print("-" * 40)
        
        for algorithm in df['algorithm'].unique():
            if algorithm == 'Sequential':
                continue
                
            algo_data = df[df['algorithm'] == algorithm]
            print(f"\n🔍 {algorithm} Scaling:")
            
            # Find optimal thread count for each depth
            for depth in sorted(algo_data['depth'].unique()):
                depth_data = algo_data[algo_data['depth'] == depth]
                if len(depth_data) < 2:
                    continue
                
                best_config = depth_data.loc[depth_data['nps'].idxmax()]
                worst_config = depth_data.loc[depth_data['nps'].idxmin()]
                
                scaling_factor = best_config['nps'] / worst_config['nps'] if worst_config['nps'] > 0 else 0
                
                print(f"   Depth {depth}: Best={best_config['threads']}t ({best_config['nps']:,.0f} NPS), "
                      f"Worst={worst_config['threads']}t ({worst_config['nps']:,.0f} NPS), "
                      f"Ratio={scaling_factor:.2f}x")
    
    def _create_comprehensive_visualizations(self, df: pd.DataFrame, results_file: str) -> None:
        """Create publication-ready visualization plots for IEEE format"""
        try:
            plt.style.use('seaborn-v0_8-darkgrid')
        except:
            plt.style.use('default')
        
        # Set color-blind safe palette
        plt.rcParams['axes.prop_cycle'] = plt.cycler('color', ['#1f77b4', '#ff7f0e', '#2ca02c', '#d62728', '#9467bd'])
        
        # Create publication-ready plots
        self._create_executive_summary_table(df, results_file)
        self._create_speedup_curves(df, results_file)  # Fig. 4
        self._create_efficiency_heatmaps(df, results_file)  # Fig. 5
        self._create_nps_vs_depth(df, results_file)  # Fig. 6
    
    def _create_nps_vs_depth(self, df: pd.DataFrame, results_file: str) -> None:
        """Create NPS vs Depth plot (Fig. 6) - single line chart showing raw horsepower"""
        plt.figure(figsize=(3.5, 2.5))  # IEEE single column width
        
        # Algorithm name mapping for cleaner labels
        algo_labels = {
            'Sequential': 'Secuencial',
            'SharedHashTable': 'Shared HT',
            'RootSplitting': 'Root Split',
            'MPI': 'MPI',
            'Hybrid': 'Híbrido'
        }
        
        for algorithm in df['algorithm'].unique():
            algo_data = df[df['algorithm'] == algorithm]
            if algorithm == 'Sequential':
                # Sequential has only one config per depth
                plt.plot(algo_data['depth'], algo_data['nps']/1e6, 'o-', 
                        label=algo_labels.get(algorithm, algorithm), 
                        linewidth=2, markersize=4)
            else:
                # Use best NPS per depth for parallel algorithms
                best_nps = algo_data.groupby('depth')['nps'].max()
                plt.plot(best_nps.index, best_nps.values/1e6, 'o-', 
                        label=algo_labels.get(algorithm, algorithm), 
                        linewidth=2, markersize=4)
        
        plt.xlabel('Profundidad', fontsize=10)
        plt.ylabel('NPS (×10⁶)', fontsize=10)
        plt.yscale('log')
        plt.grid(True, alpha=0.3)
        plt.legend(fontsize=8, loc='best')
        plt.tick_params(labelsize=8)
        plt.tight_layout()
        
        plot_file = results_file.replace('.json', '_nps_vs_depth.pdf') if results_file else 'nps_vs_depth.pdf'
        plt.savefig(plot_file, format='pdf', dpi=300, bbox_inches='tight')
        print(f"📊 Fig. 6 - NPS vs Depth saved to: {plot_file}")
        plt.show()
    
    def _create_speedup_curves(self, df: pd.DataFrame, results_file: str) -> None:
        """Create Speed-up curves (Fig. 4) - one panel per algorithm, only depths 5 and 7"""
        parallel_algs = [alg for alg in df['algorithm'].unique() if alg != 'Sequential']
        if not parallel_algs:
            return
        
        # Algorithm name mapping
        algo_labels = {
            'SharedHashTable': 'Shared HT',
            'RootSplitting': 'Root Split',
            'MPI': 'MPI',
            'Hybrid': 'Híbrido'
        }
        
        # Only show depths 5 and 7 for clarity
        depths_to_show = [5, 7]
        
        # Create subplot layout - IEEE two-column format
        n_algos = len(parallel_algs)
        if n_algos <= 4:
            fig, axes = plt.subplots(1, n_algos, figsize=(7.2, 2.0), sharey=True)
        else:
            fig, axes = plt.subplots(2, 2, figsize=(7.2, 4.0), sharey=True)
        
        if n_algos == 1:
            axes = [axes]
        
        # Get sequential baseline times
        sequential_data = df[df['algorithm'] == 'Sequential']
        seq_times = {}
        for depth in depths_to_show:
            seq_baseline = sequential_data[sequential_data['depth'] == depth]
            if not seq_baseline.empty:
                seq_times[depth] = seq_baseline['wall_time_ms'].iloc[0]
        
        for i, algorithm in enumerate(parallel_algs[:len(axes)]):
            if i >= len(axes):
                break
                
            ax = axes[i] if hasattr(axes, '__len__') else axes
            algo_data = df[df['algorithm'] == algorithm]
            
            # Plot speedup for selected depths only
            max_threads = 1
            for depth in depths_to_show:
                if depth not in seq_times:
                    continue
                    
                depth_data = algo_data[algo_data['depth'] == depth].sort_values('threads')
                if depth_data.empty:
                    continue
                
                speedups = seq_times[depth] / depth_data['wall_time_ms']
                ax.plot(depth_data['threads'], speedups, 'o-', 
                       label=f'Profundidad {depth}', markersize=4, linewidth=1.5)
                max_threads = max(max_threads, depth_data['threads'].max())
            
            # Add ideal linear scaling line
            if max_threads > 1:
                ax.plot([1, max_threads], [1, max_threads], 'k--', alpha=0.3, label='Ideal')
            
            ax.set_title(algo_labels.get(algorithm, algorithm), fontsize=10)
            ax.set_xlabel('Hilos/Procesos', fontsize=9)
            ax.grid(True, alpha=0.3)
            ax.tick_params(labelsize=8)
        
        # Set common ylabel only on first subplot
        axes[0].set_ylabel('Speed-up (vs. secuencial)', fontsize=9)
        
        # Add legend only on last subplot
        if len(axes) > 0:
            axes[-1].legend(loc='lower right', fontsize=7)
        
        plt.tight_layout()
        
        plot_file = results_file.replace('.json', '_speedup_curves.pdf') if results_file else 'speedup_curves.pdf'
        plt.savefig(plot_file, format='pdf', dpi=300, bbox_inches='tight')
        print(f"📊 Fig. 4 - Speed-up curves saved to: {plot_file}")
        plt.show()
    
    def _create_efficiency_heatmaps(self, df: pd.DataFrame, results_file: str) -> None:
        """Create Efficiency heat-maps (Fig. 5) - efficiency values across depth and threads"""
        parallel_algs = [alg for alg in df['algorithm'].unique() if alg != 'Sequential']
        if not parallel_algs:
            return
        
        # Algorithm name mapping
        algo_labels = {
            'SharedHashTable': 'Shared HT',
            'RootSplitting': 'Root Split', 
            'MPI': 'MPI',
            'Hybrid': 'Híbrido'
        }
        
        # Get sequential baseline times for efficiency calculation
        sequential_data = df[df['algorithm'] == 'Sequential']
        seq_times = {}
        for depth in df['depth'].unique():
            seq_baseline = sequential_data[sequential_data['depth'] == depth]
            if not seq_baseline.empty:
                seq_times[depth] = seq_baseline['wall_time_ms'].iloc[0]
        
        # Calculate efficiency for each algorithm
        efficiency_data = {}
        for algorithm in parallel_algs:
            algo_data = df[df['algorithm'] == algorithm].copy()
            efficiencies = []
            
            for _, row in algo_data.iterrows():
                if row['depth'] in seq_times and row['threads'] > 0 and row['wall_time_ms'] > 0:
                    speedup = seq_times[row['depth']] / row['wall_time_ms']
                    efficiency = (speedup / row['threads']) * 100
                    efficiencies.append({
                        'depth': row['depth'],
                        'threads': row['threads'],
                        'efficiency': efficiency
                    })
            
            if efficiencies:
                eff_df = pd.DataFrame(efficiencies)
                efficiency_data[algorithm] = eff_df.pivot_table(
                    index='depth', columns='threads', values='efficiency', aggfunc='mean'
                )
        
        # Create heatmaps - focus on 2 main algorithms if more than 2
        algorithms_to_plot = parallel_algs[:2] if len(parallel_algs) > 2 else parallel_algs
        
        if len(algorithms_to_plot) == 1:
            fig, ax = plt.subplots(1, 1, figsize=(3.5, 2.5))
            axes = [ax]
        else:
            fig, axes = plt.subplots(1, len(algorithms_to_plot), figsize=(7.2, 2.5))
        
        for i, algorithm in enumerate(algorithms_to_plot):
            ax = axes[i] if len(algorithms_to_plot) > 1 else axes[0]
            
            if algorithm in efficiency_data and not efficiency_data[algorithm].empty:
                # Create heatmap with efficiency values
                sns.heatmap(
                    efficiency_data[algorithm], 
                    cmap='RdYlGn', 
                    vmin=0, 
                    vmax=100,
                    annot=True, 
                    fmt='.0f', 
                    ax=ax,
                    cbar_kws={'label': 'Eficiencia (%)'} if i == len(algorithms_to_plot)-1 else {'label': ''},
                    cbar=i == len(algorithms_to_plot)-1  # Only show colorbar on last plot
                )
                ax.set_title(algo_labels.get(algorithm, algorithm), fontsize=10)
                ax.set_xlabel('Hilos/Procesos', fontsize=9)
                ax.set_ylabel('Profundidad' if i == 0 else '', fontsize=9)
            else:
                ax.text(0.5, 0.5, f'{algo_labels.get(algorithm, algorithm)}\nDatos insuficientes', 
                       ha='center', va='center', transform=ax.transAxes)
                ax.set_title(algo_labels.get(algorithm, algorithm), fontsize=10)
            
            ax.tick_params(labelsize=8)
        
        plt.tight_layout()
        
        plot_file = results_file.replace('.json', '_efficiency_heatmaps.pdf') if results_file else 'efficiency_heatmaps.pdf'
        plt.savefig(plot_file, format='pdf', dpi=300, bbox_inches='tight')
        print(f"📊 Fig. 5 - Efficiency heatmaps saved to: {plot_file}")
        plt.show()
    
    def _create_executive_summary_table(self, df: pd.DataFrame, results_file: str) -> None:
        """Create Executive Summary Table (Table I) with optimal configurations"""
        
        # Algorithm name mapping
        algo_labels = {
            'Sequential': 'Secuencial',
            'SharedHashTable': 'Shared HT',
            'RootSplitting': 'Root Split',
            'MPI': 'MPI',
            'Hybrid': 'Híbrido'
        }
        
        # Get sequential baseline for speedup calculation
        sequential_data = df[df['algorithm'] == 'Sequential']
        if sequential_data.empty:
            print("⚠️  No sequential baseline found for table generation")
            return
        
        # Find the best sequential configuration (highest NPS)
        seq_best = sequential_data.loc[sequential_data['nps'].idxmax()]
        seq_baseline_time = seq_best['wall_time_ms']
        
        print("\n" + "="*80)
        print("TABLA I: RESUMEN EJECUTIVO - CONFIGURACIONES ÓPTIMAS")
        print("="*80)
        print(f"{'Algoritmo':<15} {'Config. óptima':<18} {'Speed-up':<10} {'NPS (×10⁶)':<12} {'Eficiencia':<12}")
        print(f"{'':15} {'(prof/hilos)':<18} {'':10} {'':12} {'':12}")
        print("-"*80)
        
        # Sequential baseline
        print(f"{'Secuencial':<15} {f'{seq_best["depth"]}/{seq_best["threads"]}':<18} "
              f"{'1.00×':<10} {seq_best['nps']/1e6:<12.2f} {'–':<12}")
        
        # Table data for LaTeX export
        table_data = []
        table_data.append([
            "Secuencial", f"{seq_best['depth']}/{seq_best['threads']}", "1.00×", 
            f"{seq_best['nps']/1e6:.2f}", "–"
        ])
        
        # Parallel algorithms
        for algorithm in df['algorithm'].unique():
            if algorithm == 'Sequential':
                continue
                
            algo_data = df[df['algorithm'] == algorithm]
            if algo_data.empty:
                continue
            
            # Find optimal configuration (best NPS)
            best_config = algo_data.loc[algo_data['nps'].idxmax()]
            
            # Calculate speedup vs sequential baseline
            speedup = seq_baseline_time / best_config['wall_time_ms']
            
            # Calculate efficiency
            efficiency = (speedup / best_config['threads']) if best_config['threads'] > 0 else 0
            
            print(f"{algo_labels.get(algorithm, algorithm):<15} "
                  f"{best_config['depth']}/{best_config['threads']:<17} "
                  f"{speedup:.2f}×{'':<6} "
                  f"{best_config['nps']/1e6:<12.2f} "
                  f"{efficiency:<12.2f}")
            
            table_data.append([
                algo_labels.get(algorithm, algorithm),
                f"{best_config['depth']}/{best_config['threads']}",
                f"{speedup:.2f}×",
                f"{best_config['nps']/1e6:.2f}",
                f"{efficiency:.2f}"
            ])
        
        print("-"*80)
        
        # Export LaTeX table
        latex_file = results_file.replace('.json', '_summary_table.tex') if results_file else 'summary_table.tex'
        with open(latex_file, 'w') as f:
            f.write("% Executive Summary Table - LaTeX format\n")
            f.write("\\begin{table}[h]\n")
            f.write("\\centering\n")
            f.write("\\caption{Configuraciones óptimas y métricas principales}\n")
            f.write("\\label{tab:executive_summary}\n")
            f.write("\\small\n")
            f.write("\\begin{tabular}{|l|c|r|r|r|}\n")
            f.write("\\hline\n")
            f.write("Algoritmo & Config. óptima & Speed-up & NPS (×10⁶) & Eficiencia \\\\\n")
            f.write("& (prof/hilos) &  &  &  \\\\\n")
            f.write("\\hline\n")
            
            for row in table_data:
                f.write(f"{row[0]} & {row[1]} & {row[2]} & {row[3]} & {row[4]} \\\\\n")
            
            f.write("\\hline\n")
            f.write("\\end{tabular}\n")
            f.write("\\end{table}\n")
        
        print(f"\n📊 Table I - Executive Summary saved to: {latex_file}")
        
        # Also save as CSV for easy import
        csv_file = results_file.replace('.json', '_summary_table.csv') if results_file else 'summary_table.csv'
        import csv
        with open(csv_file, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['Algoritmo', 'Config_Optima', 'Speed_up', 'NPS_Millones', 'Eficiencia'])
            writer.writerows(table_data)
        
        print(f"📊 Table I - CSV format saved to: {csv_file}")
        print("="*80)
    
    def generate_report(self, results_file: str = None) -> str:
        """Generate a comprehensive markdown report"""
        if results_file:
            with open(results_file, 'r') as f:
                data = json.load(f)
            self.results = data['results']
            self.system_info = data['system_info']
            test_config = data.get('test_configuration', {})
        
        if not self.results:
            print("❌ No results to report")
            return None
        
        df = pd.DataFrame(self.results)
        
        # Generate report
        report_file = results_file.replace('.json', '_report.md') if results_file else 'evaluation_report.md'
        
        with open(report_file, 'w') as f:
            f.write("# Chess Engine Performance Evaluation Report\n\n")
            
            # Executive Summary
            f.write("## Executive Summary\n\n")
            f.write(f"This report presents a comprehensive performance analysis of {len(df['algorithm'].unique())} ")
            f.write("chess engine search algorithm implementations.\n\n")
            
            # System Information
            f.write("## System Information\n\n")
            f.write(f"- **CPU**: {self.system_info.get('cpu_info', 'Unknown')}\n")
            f.write(f"- **CPU Cores**: {self.system_info.get('cpu_count', 'Unknown')}\n")
            f.write(f"- **OS**: {self.system_info.get('os', 'Unknown')} {self.system_info.get('os_version', '')}\n")
            f.write(f"- **Architecture**: {self.system_info.get('architecture', 'Unknown')}\n")
            f.write(f"- **Test Date**: {self.system_info.get('timestamp', 'Unknown')}\n\n")
            
            # Test Configuration
            f.write("## Test Configuration\n\n")
            if test_config:
                f.write(f"- **Algorithms Tested**: {', '.join(test_config.get('algorithms_tested', []))}\n")
                f.write(f"- **Search Depths**: {test_config.get('depths', 'Unknown')}\n")
                f.write(f"- **Test Positions**: {', '.join(test_config.get('positions', []))}\n")
                f.write(f"- **Total Tests**: {test_config.get('total_tests', 'Unknown')}\n")
                f.write(f"- **Successful Tests**: {test_config.get('successful_tests', 'Unknown')}\n\n")
            
            # Performance Summary
            f.write("## Performance Summary\n\n")
            f.write("### Peak Performance by Algorithm\n\n")
            f.write("| Algorithm | Peak NPS | Best Config (Depth, Threads) |\n")
            f.write("|-----------|----------|------------------------------|\n")
            
            for algorithm in df['algorithm'].unique():
                algo_data = df[df['algorithm'] == algorithm]
                best_config = algo_data.loc[algo_data['nps'].idxmax()]
                f.write(f"| {algorithm} | {best_config['nps']:,} | d={best_config['depth']}, t={best_config['threads']} |\n")
            
            f.write("\n")
            
            # Parallel Efficiency Analysis
            f.write("## Parallel Efficiency Analysis\n\n")
            sequential_data = df[df['algorithm'] == 'Sequential']
            
            if not sequential_data.empty:
                for algorithm in df['algorithm'].unique():
                    if algorithm == 'Sequential':
                        continue
                    
                    f.write(f"### {algorithm}\n\n")
                    algo_data = df[df['algorithm'] == algorithm]
                    
                    f.write("| Depth | Threads | Speedup | Efficiency | NPS Ratio |\n")
                    f.write("|-------|---------|---------|------------|----------|\n")
                    
                    for depth in sorted(algo_data['depth'].unique()):
                        seq_baseline = sequential_data[sequential_data['depth'] == depth]
                        if seq_baseline.empty:
                            continue
                        
                        seq_time = seq_baseline['wall_time_ms'].iloc[0]
                        seq_nps = seq_baseline['nps'].iloc[0]
                        
                        depth_data = algo_data[algo_data['depth'] == depth]
                        for _, row in depth_data.iterrows():
                            speedup = seq_time / row['wall_time_ms'] if row['wall_time_ms'] > 0 else 0
                            efficiency = (speedup / row['threads']) * 100 if row['threads'] > 0 else 0
                            nps_ratio = row['nps'] / seq_nps if seq_nps > 0 else 0
                            
                            f.write(f"| {depth} | {row['threads']} | {speedup:.2f} | {efficiency:.1f}% | {nps_ratio:.2f} |\n")
                    
                    f.write("\n")
            
            # Recommendations
            f.write("## Recommendations\n\n")
            f.write("### Optimal Configurations\n\n")
            
            for algorithm in df['algorithm'].unique():
                if algorithm == 'Sequential':
                    continue
                    
                algo_data = df[df['algorithm'] == algorithm]
                f.write(f"**{algorithm}:**\n")
                
                for depth in sorted(algo_data['depth'].unique()):
                    depth_data = algo_data[algo_data['depth'] == depth]
                    best_config = depth_data.loc[depth_data['nps'].idxmax()]
                    f.write(f"- Depth {depth}: {best_config['threads']} threads/processes ({best_config['nps']:,} NPS)\n")
                
                f.write("\n")
            
            # Conclusions
            f.write("## Conclusions\n\n")
            best_overall = df.loc[df['nps'].idxmax()]
            f.write(f"- **Best Overall Performance**: {best_overall['algorithm']} achieved {best_overall['nps']:,} NPS ")
            f.write(f"at depth {best_overall['depth']} with {best_overall['threads']} threads/processes\n\n")
            
            # Calculate average speedup for each parallel algorithm
            for algorithm in df['algorithm'].unique():
                if algorithm == 'Sequential':
                    continue
                
                algo_data = df[df['algorithm'] == algorithm]
                speedups = []
                
                for _, row in algo_data.iterrows():
                    seq_baseline = sequential_data[sequential_data['depth'] == row['depth']]
                    if not seq_baseline.empty:
                        seq_time = seq_baseline['wall_time_ms'].iloc[0]
                        speedup = seq_time / row['wall_time_ms'] if row['wall_time_ms'] > 0 else 0
                        speedups.append(speedup)
                
                if speedups:
                    avg_speedup = np.mean(speedups)
                    f.write(f"- **{algorithm}**: Average speedup of {avg_speedup:.2f}x over sequential baseline\n")
            
            f.write(f"\n---\n*Report generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*\n")
        
        print(f"📋 Comprehensive report saved to: {report_file}")
        return report_file

def main():
    parser = argparse.ArgumentParser(description='Definitive Chess Engine Evaluation Tool')
    parser.add_argument('--quick', action='store_true', help='Run quick evaluation (fewer tests)')
    parser.add_argument('--analyze', help='Analyze existing results file (.json)')
    parser.add_argument('--report', help='Generate report from existing results file (.json)')
    parser.add_argument('--output-dir', default='results', help='Output directory for results')
    
    args = parser.parse_args()
    
    evaluator = ChessEngineEvaluator(output_dir=args.output_dir)
    
    if args.analyze:
        if not os.path.exists(args.analyze):
            print(f"❌ Results file not found: {args.analyze}")
            return
        evaluator.analyze_results(args.analyze)
    elif args.report:
        if not os.path.exists(args.report):
            print(f"❌ Results file not found: {args.report}")
            return
        evaluator.generate_report(args.report)
    else:
        # Run evaluation
        results_file = evaluator.run_comprehensive_evaluation(quick_mode=args.quick)
        if results_file:
            print(f"\n🎯 Evaluation completed successfully!")
            print(f"📁 Results: {results_file}")
            
            # Automatically analyze results
            print(f"\n📊 Analyzing results...")
            evaluator.analyze_results(results_file)
            
            # Generate report
            print(f"\n📋 Generating comprehensive report...")
            report_file = evaluator.generate_report(results_file)
            
            print(f"\n✅ Complete evaluation finished!")
            print(f"   📊 Visualizations: Multiple PNG files in {args.output_dir}/")
            print(f"   📋 Report: {report_file}")
            print(f"   💾 Raw data: {results_file}")

if __name__ == "__main__":
    main() 