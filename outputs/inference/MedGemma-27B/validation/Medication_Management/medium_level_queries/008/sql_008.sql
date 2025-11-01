WITH CTE1 AS (
  SELECT ...
  WHERE condition1 AND condition2 -- Error likely here or just before
), CTE2 AS (
  SELECT ...
)
SELECT ...;