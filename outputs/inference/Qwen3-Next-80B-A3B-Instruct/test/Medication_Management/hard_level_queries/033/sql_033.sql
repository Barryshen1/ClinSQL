SELECT
  'Group Summary' AS category,
  drug_group,
  COUNT(*) AS n_patients,
  AVG(complexity_score) AS mean_complexity,
  PERCENTILE_CONT(complexity_score, 0.5) OVER () AS median_complexity_overall,  -- ❌ ERROR HERE
  MIN(complexity_score) AS min_complexity,
  MAX(complexity_score) AS max_complexity
FROM grouped_patients
GROUP BY drug_group;