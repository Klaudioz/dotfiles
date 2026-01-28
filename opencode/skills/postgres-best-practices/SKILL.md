---
name: postgres-best-practices
description: Supabase Postgres performance optimization and best practices. Use when writing/reviewing SQL queries, designing schemas, implementing indexes, optimizing RLS policies, configuring connection pooling, or diagnosing database performance issues.
---

# Supabase Postgres Best Practices

Comprehensive Postgres performance optimization guide from Supabase. Contains 30+ rules across 8 categories, prioritized by impact.

## When to Apply

Reference these guidelines when:
- Writing SQL queries or designing schemas
- Implementing indexes or query optimization
- Reviewing database performance issues
- Configuring connection pooling or scaling
- Optimizing for Postgres-specific features
- Working with Row-Level Security (RLS)

## Rule Categories by Priority

| Priority | Category | Impact | Prefix |
|----------|----------|--------|--------|
| 1 | Query Performance | CRITICAL | `query-` |
| 2 | Connection Management | CRITICAL | `conn-` |
| 3 | Security & RLS | CRITICAL | `security-` |
| 4 | Schema Design | HIGH | `schema-` |
| 5 | Concurrency & Locking | MEDIUM-HIGH | `lock-` |
| 6 | Data Access Patterns | MEDIUM | `data-` |
| 7 | Monitoring & Diagnostics | LOW-MEDIUM | `monitor-` |
| 8 | Advanced Features | LOW | `advanced-` |

## Quick Reference: Critical Rules

### 1. Query Performance (CRITICAL)

**1.1 Add Indexes on WHERE and JOIN Columns** - 100-1000x faster queries

```sql
-- WRONG: No index causes full table scan
select * from orders where customer_id = 123;

-- CORRECT: Create index on filtered columns
create index orders_customer_id_idx on orders (customer_id);
```

**1.2 Choose the Right Index Type**

| Index Type | Use For |
|------------|---------|
| B-tree (default) | `=`, `<`, `>`, `BETWEEN`, `IN`, `IS NULL` |
| GIN | Arrays, JSONB, full-text search |
| BRIN | Large time-series tables (10-100x smaller) |
| Hash | Equality-only (slightly faster than B-tree for `=`) |

**1.3 Create Composite Indexes** - 5-10x faster multi-column queries

```sql
-- Place equality columns first, range columns last
create index orders_status_created_idx on orders (status, created_at);
```

**1.4 Use Covering Indexes** - 2-5x faster by avoiding table lookups

```sql
create index users_email_idx on users (email) include (name, created_at);
```

**1.5 Use Partial Indexes** - 5-20x smaller indexes

```sql
create index users_active_email_idx on users (email) where deleted_at is null;
```

### 2. Connection Management (CRITICAL)

**2.1 Use Connection Pooling** - Handle 10-100x more concurrent users

```sql
-- Use PgBouncer or Supabase connection pooler
-- pool_size = (CPU cores * 2) + spindle_count
```

**2.2 Configure Idle Connection Timeouts**

```sql
alter system set idle_in_transaction_session_timeout = '30s';
alter system set idle_session_timeout = '10min';
```

**2.3 Set Appropriate Connection Limits**

```sql
-- Formula: max_connections = (RAM in MB / 5MB) - reserved
-- For 4GB RAM: max_connections = 100
```

### 3. Security & RLS (CRITICAL)

**3.1 Enable Row Level Security**

```sql
alter table orders enable row level security;

create policy orders_user_policy on orders
  for all
  to authenticated
  using ((select auth.uid()) = user_id);  -- Wrap in SELECT for performance!
```

**3.2 Optimize RLS Policies** - 5-10x faster with proper patterns

```sql
-- WRONG: Function called per row
using (auth.uid() = user_id);

-- CORRECT: Function called once, cached
using ((select auth.uid()) = user_id);
```

**3.3 Always Index RLS Columns**

```sql
create index orders_user_id_idx on orders (user_id);
```

### 4. Schema Design (HIGH)

**4.1 Choose Appropriate Data Types**

| Use | Instead Of | Why |
|-----|------------|-----|
| `bigint` | `int` | Future-proofing (9 quintillion max) |
| `text` | `varchar(n)` | Same performance, no artificial limit |
| `timestamptz` | `timestamp` | Always store timezone info |
| `numeric(10,2)` | `float` | Exact decimal arithmetic |
| `boolean` | `varchar(5)` | 1 byte vs variable length |

**4.2 Index Foreign Key Columns** - 10-100x faster JOINs and CASCADE

```sql
create table orders (
  customer_id bigint references customers(id) on delete cascade
);
create index orders_customer_id_idx on orders (customer_id);
```

**4.3 Use IDENTITY for Primary Keys**

```sql
create table users (
  id bigint generated always as identity primary key
);
```

### 5. Concurrency & Locking (MEDIUM-HIGH)

**5.1 Keep Transactions Short**

```sql
-- Do API calls OUTSIDE the transaction
-- Only hold locks for actual updates
```

**5.2 Prevent Deadlocks** - Lock rows in consistent order

```sql
select * from accounts where id in (1, 2) order by id for update;
```

**5.3 Use SKIP LOCKED for Queues** - 10x throughput

```sql
select * from jobs
where status = 'pending'
order by created_at
limit 1
for update skip locked;
```

### 6. Data Access Patterns (MEDIUM)

**6.1 Eliminate N+1 Queries**

```sql
-- WRONG: Loop with individual queries
-- CORRECT: Single batch query
select * from orders where user_id = any($1::bigint[]);
```

**6.2 Use Cursor-Based Pagination** - O(1) regardless of page depth

```sql
-- WRONG: OFFSET gets slower on deeper pages
select * from products order by id limit 20 offset 1980;

-- CORRECT: Cursor pagination
select * from products where id > 20 order by id limit 20;
```

**6.3 Use UPSERT for Insert-or-Update**

```sql
insert into settings (user_id, key, value)
values (123, 'theme', 'dark')
on conflict (user_id, key)
do update set value = excluded.value;
```

### 7. Monitoring & Diagnostics (LOW-MEDIUM)

**7.1 Use EXPLAIN ANALYZE**

```sql
explain (analyze, buffers, format text)
select * from orders where customer_id = 123;
```

**7.2 Enable pg_stat_statements**

```sql
create extension if not exists pg_stat_statements;

select query, calls, mean_exec_time
from pg_stat_statements
order by total_exec_time desc
limit 10;
```

### 8. Advanced Features (LOW)

**8.1 Index JSONB Columns**

```sql
create index products_attrs_idx on products using gin (attributes);
```

**8.2 Use tsvector for Full-Text Search**

```sql
alter table articles add column search_vector tsvector;
create index articles_search_idx on articles using gin (search_vector);
```

## Full Reference

For complete explanations with EXPLAIN output and detailed examples, see:
`references/postgres_best_practices.md`

## Source

Maintained by Supabase. Original: https://github.com/supabase/agent-skills
