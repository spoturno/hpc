#!/usr/bin/env python3
"""
Chess Engine Performance Analysis Script
Analyzes results from depth_thread_evaluation.sh
"""

import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import sys
import os
import glob
import argparse
from pathlib import Path

def load_latest_results():
    """Load the most recent results file"""
    results_dir = Path("results")
    if not results_dir.exists():
        print("❌ Results directory not found. Run depth_thread_evaluation.sh first.")
        return None
    
    csv_files = glob.glob("results/depth_thread_evaluation_*.csv")
    if not csv_files:
        print("❌ No evaluation results found. Run depth_thread_evaluation.sh first.")
        return None
    
    latest_file = max(csv_files, key=os.path.getctime)
    print(f"📊 Loading results from: {latest_file}")
    
    try:
        df = pd.read_csv(latest_file)
        # Clean data - remove ERROR rows
        df = df[df['Nodes'] != 'ERROR'].copy()
        
        # Handle both old and new column names for threads/processes
        if 'Threads/Processes' in df.columns:
            df['Threads'] = df['Threads/Processes']
        elif 'Threads' not in df.columns:
            print("❌ Neither 'Threads' nor 'Threads/Processes' column found in CSV")
            return None
        
        # Convert numeric columns
        numeric_cols = ['Depth', 'Threads', 'Nodes', 'EngineTime(ms)', 'WallTime(ms)', 'NPS', 'Score']
        for col in numeric_cols:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors='coerce')
        
        return df, latest_file
    except Exception as e:
        print(f"❌ Error loading results: {e}")
        return None

def print_summary_stats(df):
    """Print summary statistics"""
    print("\n" + "="*60)
    print("📈 PERFORMANCE SUMMARY")
    print("="*60)
    
    print(f"\n🔢 Total valid evaluations: {len(df)}")
    print(f"📊 Algorithms tested: {', '.join(df['Algorithm'].unique())}")
    print(f"🔍 Depth range: {df['Depth'].min()}-{df['Depth'].max()}")
    print(f"🧵 Thread/Process counts: {sorted(df['Threads'].unique())}")
    
    print(f"\n⚡ Performance Ranges:")
    print(f"   Nodes: {df['Nodes'].min():,} - {df['Nodes'].max():,}")
    print(f"   Time: {df['WallTime(ms)'].min():.0f}ms - {df['WallTime(ms)'].max():.0f}ms")
    print(f"   NPS: {df['NPS'].min():,} - {df['NPS'].max():,}")
    
    # Algorithm-specific summaries
    for algorithm in df['Algorithm'].unique():
        algo_data = df[df['Algorithm'] == algorithm]
        best_nps = algo_data['NPS'].max()
        best_config = algo_data.loc[algo_data['NPS'].idxmax()]
        
        if algorithm == 'Sequential':
            print(f"\n   📊 {algorithm}: Peak NPS = {best_nps:,.0f}")
        elif algorithm == 'MPI':
            print(f"   📊 {algorithm}: Peak NPS = {best_nps:,.0f} (depth {best_config['Depth']}, {best_config['Threads']} processes)")
        else:
            print(f"   📊 {algorithm}: Peak NPS = {best_nps:,.0f} (depth {best_config['Depth']}, {best_config['Threads']} threads)")

def analyze_scaling_efficiency(df):
    """Analyze parallel scaling efficiency"""
    print(f"\n🚀 PARALLEL SCALING ANALYSIS")
    print("="*60)
    
    # For each parallel algorithm, compare with sequential baseline
    sequential_data = df[df['Algorithm'] == 'Sequential'].copy()
    
    parallel_algorithms = ['SharedHashTable', 'RootSplitting', 'MPI']
    available_algorithms = [alg for alg in parallel_algorithms if alg in df['Algorithm'].unique()]
    
    for algorithm in available_algorithms:
        algo_data = df[df['Algorithm'] == algorithm].copy()
        if algo_data.empty:
            continue
            
        print(f"\n📊 {algorithm} Scaling:")
        print(f"{'Depth':<6} {'Threads':<8} {'Speedup':<10} {'Efficiency':<12} {'NPS Ratio':<10}")
        print("-" * 50)
        
        for depth in sorted(algo_data['Depth'].unique()):
            seq_time = sequential_data[sequential_data['Depth'] == depth]['WallTime(ms)']
            if seq_time.empty:
                continue
            seq_time = seq_time.iloc[0]
            
            depth_data = algo_data[algo_data['Depth'] == depth].copy()
            for _, row in depth_data.iterrows():
                speedup = seq_time / row['WallTime(ms)'] if row['WallTime(ms)'] > 0 else 0
                efficiency = speedup / row['Threads'] * 100 if row['Threads'] > 0 else 0
                
                # NPS ratio compared to sequential
                seq_nps = sequential_data[sequential_data['Depth'] == depth]['NPS']
                nps_ratio = row['NPS'] / seq_nps.iloc[0] if not seq_nps.empty and seq_nps.iloc[0] > 0 else 0
                
                threads_or_processes = "processes" if algorithm == "MPI" else "threads"
                print(f"{depth:<6} {row['Threads']:<8} {speedup:<10.2f} {efficiency:<12.1f}% {nps_ratio:<10.2f}")

def compare_parallelization_approaches(df):
    """Compare MPI vs OpenMP approaches when both are available"""
    if 'MPI' not in df['Algorithm'].unique():
        return
        
    print(f"\n🔄 MPI vs OpenMP COMPARISON")
    print("="*60)
    
    openmp_algorithms = ['SharedHashTable', 'RootSplitting']
    available_openmp = [alg for alg in openmp_algorithms if alg in df['Algorithm'].unique()]
    
    if not available_openmp:
        print("No OpenMP algorithms available for comparison")
        return
    
    mpi_data = df[df['Algorithm'] == 'MPI'].copy()
    
    print(f"\n📊 Peak Performance Comparison (Best NPS per depth):")
    print(f"{'Depth':<6} {'MPI (proc)':<15} {'Best OpenMP':<15} {'MPI Advantage':<12}")
    print("-" * 60)
    
    for depth in sorted(df['Depth'].unique()):
        # Best MPI performance for this depth
        mpi_depth = mpi_data[mpi_data['Depth'] == depth]
        if mpi_depth.empty:
            continue
        best_mpi_nps = mpi_depth['NPS'].max()
        best_mpi_config = mpi_depth.loc[mpi_depth['NPS'].idxmax()]
        
        # Best OpenMP performance for this depth
        best_openmp_nps = 0
        best_openmp_alg = ""
        for openmp_alg in available_openmp:
            openmp_depth = df[(df['Algorithm'] == openmp_alg) & (df['Depth'] == depth)]
            if not openmp_depth.empty:
                max_nps = openmp_depth['NPS'].max()
                if max_nps > best_openmp_nps:
                    best_openmp_nps = max_nps
                    best_openmp_alg = openmp_alg
        
        if best_openmp_nps > 0:
            advantage = (best_mpi_nps / best_openmp_nps - 1) * 100
            advantage_str = f"{advantage:+.1f}%"
            mpi_str = f"{best_mpi_nps:,.0f} ({best_mpi_config['Threads']}p)"
            openmp_str = f"{best_openmp_nps:,.0f} ({best_openmp_alg})"
            print(f"{depth:<6} {mpi_str:<15} {openmp_str:<15} {advantage_str:<12}")

def find_optimal_configurations(df):
    """Find optimal thread/process counts for each depth and algorithm"""
    print(f"\n🎯 OPTIMAL CONFIGURATIONS")
    print("="*60)
    
    parallel_algorithms = ['SharedHashTable', 'RootSplitting', 'MPI']
    available_algorithms = [alg for alg in parallel_algorithms if alg in df['Algorithm'].unique()]
    
    for algorithm in available_algorithms:
        algo_data = df[df['Algorithm'] == algorithm].copy()
        if algo_data.empty:
            continue
        
        threads_or_processes = "processes" if algorithm == "MPI" else "threads"
        print(f"\n⚡ {algorithm} - Best {threads_or_processes} count per depth (by NPS):")
        header = f"Best {threads_or_processes.title()}"
        print(f"{'Depth':<6} {header:<12} {'NPS':<12} {'Time(ms)':<10}")
        print("-" * 40)
        
        for depth in sorted(algo_data['Depth'].unique()):
            depth_data = algo_data[algo_data['Depth'] == depth].copy()
            best_config = depth_data.loc[depth_data['NPS'].idxmax()]
            
            print(f"{depth:<6} {best_config['Threads']:<12} {best_config['NPS']:<12,.0f} {best_config['WallTime(ms)']:<10.0f}")

def create_visualizations(df, output_file):
    """Create performance visualization plots"""
    try:
        plt.style.use('seaborn-v0_8')
    except:
        plt.style.use('default')
    
    fig, axes = plt.subplots(2, 2, figsize=(15, 12))
    fig.suptitle('Chess Engine Performance Analysis', fontsize=16, fontweight='bold')
    
    # 1. NPS vs Depth for all algorithms
    ax1 = axes[0, 0]
    for algorithm in df['Algorithm'].unique():
        algo_data = df[df['Algorithm'] == algorithm]
        if algorithm == 'Sequential':
            ax1.plot(algo_data['Depth'], algo_data['NPS'], 'o-', label=algorithm, linewidth=2, markersize=6)
        else:
            # For parallel algorithms, use best NPS per depth
            best_nps = algo_data.groupby('Depth')['NPS'].max()
            ax1.plot(best_nps.index, best_nps.values, 'o-', label=f'{algorithm} (best)', linewidth=2, markersize=6)
    
    ax1.set_xlabel('Search Depth')
    ax1.set_ylabel('Nodes Per Second')
    ax1.set_title('Peak Performance vs Depth')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    
    # 2. Scaling efficiency heatmap for SharedHashTable
    ax2 = axes[0, 1]
    sht_data = df[df['Algorithm'] == 'SharedHashTable'].copy()
    if not sht_data.empty:
        pivot_data = sht_data.pivot(index='Depth', columns='Threads', values='NPS')
        sns.heatmap(pivot_data, annot=True, fmt='.0f', ax=ax2, cmap='YlOrRd')
        ax2.set_title('SharedHashTable NPS Heatmap')
    else:
        ax2.text(0.5, 0.5, 'SharedHashTable\nNot Available', ha='center', va='center', transform=ax2.transAxes)
        ax2.set_title('SharedHashTable NPS Heatmap')
    
    # 3. Scaling efficiency heatmap for RootSplitting or MPI
    ax3 = axes[1, 0]
    
    # Prefer MPI if available, otherwise use RootSplitting
    if 'MPI' in df['Algorithm'].unique():
        mpi_data = df[df['Algorithm'] == 'MPI'].copy()
        if not mpi_data.empty:
            pivot_data = mpi_data.pivot(index='Depth', columns='Threads', values='NPS')
            sns.heatmap(pivot_data, annot=True, fmt='.0f', ax=ax3, cmap='Greens')
            ax3.set_title('MPI NPS Heatmap (Processes)')
        else:
            ax3.text(0.5, 0.5, 'MPI\nNo Data', ha='center', va='center', transform=ax3.transAxes)
            ax3.set_title('MPI NPS Heatmap (Processes)')
    else:
        rs_data = df[df['Algorithm'] == 'RootSplitting'].copy()
        if not rs_data.empty:
            pivot_data = rs_data.pivot(index='Depth', columns='Threads', values='NPS')
            sns.heatmap(pivot_data, annot=True, fmt='.0f', ax=ax3, cmap='YlGnBu')
            ax3.set_title('RootSplitting NPS Heatmap')
        else:
            ax3.text(0.5, 0.5, 'RootSplitting\nNot Available', ha='center', va='center', transform=ax3.transAxes)
            ax3.set_title('RootSplitting NPS Heatmap')
    
    # 4. Wall time comparison
    ax4 = axes[1, 1]
    for algorithm in df['Algorithm'].unique():
        algo_data = df[df['Algorithm'] == algorithm]
        if algorithm == 'Sequential':
            ax4.semilogy(algo_data['Depth'], algo_data['WallTime(ms)'], 'o-', label=algorithm, linewidth=2, markersize=6)
        else:
            # For parallel algorithms, use best time per depth
            best_time = algo_data.groupby('Depth')['WallTime(ms)'].min()
            ax4.semilogy(best_time.index, best_time.values, 'o-', label=f'{algorithm} (best)', linewidth=2, markersize=6)
    
    ax4.set_xlabel('Search Depth')
    ax4.set_ylabel('Wall Time (ms, log scale)')
    ax4.set_title('Execution Time vs Depth')
    ax4.legend()
    ax4.grid(True, alpha=0.3)
    
    plt.tight_layout()
    
    # Save plot
    plot_file = output_file.replace('.csv', '_analysis.png')
    plt.savefig(plot_file, dpi=300, bbox_inches='tight')
    print(f"\n📊 Visualization saved to: {plot_file}")
    
    # Show plot if in interactive mode
    try:
        plt.show()
    except:
        pass

def main():
    parser = argparse.ArgumentParser(description='Analyze chess engine performance results')
    parser.add_argument('--csv', help='Specific CSV file to analyze')
    parser.add_argument('--no-plot', action='store_true', help='Skip generating plots')
    args = parser.parse_args()
    
    print("🔍 Chess Engine Performance Analyzer")
    print("=" * 40)
    
    if args.csv:
        if not os.path.exists(args.csv):
            print(f"❌ File not found: {args.csv}")
            return
        df = pd.read_csv(args.csv)
        output_file = args.csv
    else:
        result = load_latest_results()
        if result is None:
            return
        df, output_file = result
    
    if df.empty:
        print("❌ No valid data to analyze")
        return
    
    # Perform analysis
    print_summary_stats(df)
    analyze_scaling_efficiency(df)
    compare_parallelization_approaches(df)
    find_optimal_configurations(df)
    
    # Create visualizations
    if not args.no_plot:
        try:
            create_visualizations(df, output_file)
        except ImportError:
            print("\n⚠️  Matplotlib/Seaborn not available. Install with:")
            print("    pip install matplotlib seaborn")
        except Exception as e:
            print(f"\n⚠️  Could not create plots: {e}")
    
    print(f"\n✅ Analysis complete!")

if __name__ == "__main__":
    main() 