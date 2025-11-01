SELECT 
  '90th_percentile_score' AS metric_type,
  CAST(p90_score AS STRING) AS metric_value,
  NULL AS lab,
  NULL AS group_name
FROM tmp.percentile_calc

UNION ALL

SELECT 
  'mortality_rate',
  CAST(AVG(mortality) AS STRING),
  NULL,
  'top_tier'
FROM tmp.top_tier_outcomes

UNION ALL

SELECT 
  'avg_los_days',
  CAST(AVG(los_days) AS STRING),
  NULL,
  'top_tier'
FROM tmp.top_tier_outcomes

UNION ALL

SELECT 
  'critical_rate',
  CAST(top_tier_critical_rate AS STRING),
  lab,
  'top_tier'
FROM tmp.top_tier_critical_rates

UNION ALL

SELECT 
  'critical_rate',
  CAST(cohort_critical_rate AS STRING),
  lab,
  'cohort'
FROM tmp.cohort_critical_rates
ORDER BY metric_type, lab, group_name;