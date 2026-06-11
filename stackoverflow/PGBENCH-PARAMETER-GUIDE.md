# pgbench Parameter Guide - Complete Reference

## 📋 Overview

The `run-workload-test-pgbench.sh` script has been enhanced with flexible command-line parameters to support various testing scenarios.

---

## 🚀 Quick Start

```bash
# No parameters - uses defaults (8 threads, 500 iterations)
./run-workload-test-pgbench.sh

# Show help and examples
./run-workload-test-pgbench.sh --help

# Custom parameters
./run-workload-test-pgbench.sh --threads 4 --iterations 250
```

---

## 📝 Parameters

### `--threads NUM`
- Number of concurrent database connections
- Default: **8**
- Range: Any positive integer (1, 2, 4, 8, 16, 32, etc.)
- Impact: Higher threads = more concurrent load

### `--iterations NUM`
- Number of transactions per thread
- Default: **500**
- Range: Any positive integer (10, 100, 500, 1000, etc.)
- Impact: Higher iterations = more total queries

### `-h, --help`
- Display usage information and examples
- Exits after showing help

---

## 🎯 Common Use Cases

### 1. Smoke Test (Quick Validation)
```bash
./run-workload-test-pgbench.sh --threads 2 --iterations 50
# Result: 100 total queries across 2 threads
# Time: < 1 minute
```

### 2. Standard Test (Default)
```bash
./run-workload-test-pgbench.sh
# Result: 4,000 queries across 8 threads
# Time: 5-10 minutes (depending on query complexity)
```

### 3. Load Test (Heavy)
```bash
./run-workload-test-pgbench.sh --threads 16 --iterations 1000
# Result: 16,000 queries across 16 threads
# Time: 15-30 minutes
```

### 4. Stress Test (Extreme)
```bash
./run-workload-test-pgbench.sh --threads 32 --iterations 2000
# Result: 64,000 queries across 32 threads
# Time: 30-60 minutes
```

### 5. Single-threaded Validation
```bash
./run-workload-test-pgbench.sh --threads 1 --iterations 500
# Result: 500 sequential queries
# Time: < 5 minutes
# Use: Verify functionality without concurrency
```

---

## 📊 Parameter Combinations

| Threads | Iterations | Total | Purpose |
|---------|-----------|-------|---------|
| 1 | 100 | 100 | Quick validation |
| 2 | 50 | 100 | Smoke test |
| 4 | 250 | 1,000 | Light load |
| 8 | 500 | 4,000 | Standard test |
| 16 | 500 | 8,000 | Heavy load |
| 16 | 1000 | 16,000 | Stress test |
| 32 | 1000 | 32,000 | High stress |

---

## ✅ Verification Examples

Test that parameters work correctly:

```bash
# Should show help
./run-workload-test-pgbench.sh --help

# Should display "Threads: 4"
./run-workload-test-pgbench.sh --threads 4 2>&1 | grep "Threads:"

# Should display "Total queries to execute: 5000"
./run-workload-test-pgbench.sh --threads 2 --iterations 2500 2>&1 | grep "Total"
```

---

## 🔄 Parameter Order

Parameters work in any order:

```bash
# All equivalent
./run-workload-test-pgbench.sh --threads 4 --iterations 250
./run-workload-test-pgbench.sh --iterations 250 --threads 4
```

---

## 📄 Output Example

```
==========================================
PostgreSQL Workload Testing - pgbench
==========================================
Database: stackoverflow2013
Threads: 4
Iterations per thread: 250
Total queries to execute: 1000
Function: usp_randomq()

Test SQL:
SELECT * FROM usp_randomq() LIMIT 1;

==========================================
Starting workload test...
==========================================

pgbench (16.14 (Ubuntu 16.14-1.pgdg24.04+1))
...
```

---

## 📚 Related Documentation

- **IMPLEMENTATION-SUMMARY.md** - Technical details of changes
- **PGBENCH-QUICK-REFERENCE.txt** - Quick lookup table
- **PGBENCH-SCRIPT-UPDATE.md** - Changelog

---

**Status**: ✅ PRODUCTION READY

All parameters tested and verified. Use this guide for flexible workload testing.
