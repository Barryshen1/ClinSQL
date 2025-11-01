WITH 
-- ... (previous CTEs remain the same)

-- Final query to get the required statistics
SELECT 
  APPROX_QUANTILES(li.lab_instability_score, 100)[OFFSET(25)] AS percentile_25_lab_instability,
  AVG(co.los_hours) AS avg_los_hours,
  SUM(co.mortality_flag) / COUNT(co.hadm_id) AS mortality_rate,
  (SELECT COUNT(*) FROM critical_lab_events WHERE hadm_id IN (SELECT hadm_id FROM cohort)) / COUNT(DISTINCT c.hadm_id) AS cohort_critical_lab_freq,
  (SELECT COUNT(*) FROM critical_lab_events) / (SELECT COUNT(DISTINCT hadm_id) FROM `physionet-data.mimiciv_3_1_hosp.admissions`) AS general_critical_lab_freq
FROM cohort_outcomes co
JOIN cohort c ON co.hadm_id = c.hadm_id
JOIN lab_instability li ON co.hadm_id = li.hadm_id;