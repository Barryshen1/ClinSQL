SELECT
  has_icu_stay,
  CASE
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  AVG(num_ultrasounds) AS mean_ultrasounds_per_admission;