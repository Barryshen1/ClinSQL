WITH 
-- ... (CTEs remain the same until top_quartile_outcomes)

-- Final analysis
SELECT 
  group_label,
  PERCENTILE_CONT(score, 0.95) AS percentile_95_instability,
  AVG(hospital_mortality) AS avg_hospital_mortality,
  AVG(icu_los) AS avg_icu_los,
  AVG(had_fever) AS prop_had_fever,
  AVG(had_low_spo2) AS prop_had_low_spo2,
  AVG(had_high_rr) AS prop_had_high_rr
FROM top_quartile_outcomes
GROUP BY group_label;