SELECT 
  'Acute Respiratory Failure' AS cohort,
  AVG(avg_instability_burden) AS avg_burden,
  APPROX_QUANTILES(avg_instability_burden, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(avg_instability_burden, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(avg_instability_burden, 100)[OFFSET(75)] AS p75,
  ...;