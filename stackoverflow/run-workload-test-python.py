#!/usr/bin/env python3
"""
PostgreSQL Workload Test (Equivalent to SqlQueryStress)
Runs usp_randomq() with configurable threads and iterations
"""

import psycopg2
import threading
import time
import sys
from datetime import datetime

# Configuration
DB_CONFIG = {
    'host': 'localhost',
    'database': 'stackoverflow2013',
    'user': 'postgres',
    'password': None  # Use .pgpass or environment
}

THREADS = 6
ITERATIONS_PER_THREAD = 500
QUERY = "SELECT * FROM usp_randomq() LIMIT 1;"

# Shared metrics
metrics = {
    'total_queries': 0,
    'successful': 0,
    'errors': 0,
    'lock': threading.Lock(),
    'start_time': None,
    'end_time': None,
}

def worker(thread_id, iterations):
    """Worker thread - executes queries"""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        for i in range(iterations):
            try:
                cursor.execute(QUERY)
                cursor.fetchall()
                
                with metrics['lock']:
                    metrics['successful'] += 1
                    metrics['total_queries'] += 1
                
                # Progress
                if (i + 1) % 50 == 0:
                    print(f"[Thread {thread_id}] Completed {i + 1}/{iterations} queries")
            
            except Exception as e:
                with metrics['lock']:
                    metrics['errors'] += 1
                    metrics['total_queries'] += 1
                print(f"[Thread {thread_id}] Error on query {i + 1}: {e}")
        
        cursor.close()
        conn.close()
        print(f"[Thread {thread_id}] COMPLETED")
    
    except Exception as e:
        print(f"[Thread {thread_id}] Connection error: {e}")
        with metrics['lock']:
            metrics['errors'] += iterations

def main():
    print("=" * 60)
    print("PostgreSQL Workload Test")
    print("=" * 60)
    print(f"Database: {DB_CONFIG['database']}")
    print(f"Threads: {THREADS}")
    print(f"Iterations per thread: {ITERATIONS_PER_THREAD}")
    print(f"Total queries: {THREADS * ITERATIONS_PER_THREAD}")
    print(f"Query: {QUERY}")
    print("=" * 60)
    print()
    
    metrics['start_time'] = time.time()
    threads = []
    
    # Start all threads
    for i in range(THREADS):
        t = threading.Thread(target=worker, args=(i + 1, ITERATIONS_PER_THREAD))
        threads.append(t)
        t.start()
    
    # Wait for all threads
    for t in threads:
        t.join()
    
    metrics['end_time'] = time.time()
    duration = metrics['end_time'] - metrics['start_time']
    
    print()
    print("=" * 60)
    print("RESULTS")
    print("=" * 60)
    print(f"Total queries executed: {metrics['total_queries']}")
    print(f"Successful: {metrics['successful']}")
    print(f"Errors: {metrics['errors']}")
    print(f"Duration: {duration:.2f} seconds")
    print(f"Queries per second: {metrics['total_queries'] / duration:.2f}")
    print("=" * 60)

if __name__ == '__main__':
    main()
