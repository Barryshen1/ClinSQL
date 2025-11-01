WITH mean_dka_apache AS (
  SELECT AVG(apache_iv_score) AS mean_apache_dka
  FROM cohort_with_outcomes
  WHERE has_dka = 1 AND apache_iv_score IS NOT NULL
),
percentile_calc AS (
  SELECT 
    1.0 * SUM(CASE WHEN co.apache_iv_score <= m.mean_apache_dka THEN 1 ELSE 0 END) / COUNT(*) AS percentile
  FROM cohort_with_outcomes co
  CROSS JOIN mean_dka_apache m
  WHERE co.apache_iv_score IS NOT NULL
);