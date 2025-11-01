SELECT
  COUNT(*) AS num_patients,
  ROUND(APPROX_QUANTILES(hs_tnt_ngml, 4)[OFFSET(2)], 4) AS median_ng_per_ml,
  ROUND(APPROX_QUANTILES(hs_tnt_ngml, 4)[OFFSET(1)], 4) AS q1_ng_per_ml,
  ROUND(APPROX_QUANTILES(hs_tnt_ngml, 4)[OFFSET(3)], 4) AS q3_ng_per_ml
FROM above_uln;