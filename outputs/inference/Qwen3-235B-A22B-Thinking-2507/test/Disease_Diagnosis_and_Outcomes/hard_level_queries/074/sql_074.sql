with actual IDs)
patient_info AS (
  SELECT 
    (SELECT pesi_score 
     FROM pesi_scores 
     WHERE subject_id = 123 AND hadm_id = 456) AS patient_risk_score,
    -- Calculate the percentile among patients with non-NULL PESI score
    (SELECT 
        COUNT(*) 
     FROM pesi_scores 
     WHERE pesi_score IS NOT NULL 
       AND pesi_score <= (SELECT pesi_score FROM pesi_scores WHERE subject_id = 123 AND hadm_id = 456)
    ) * 1.0 / 
    (SELECT COUNT(*) FROM pesi_scores WHERE pesi_score IS NOT NULL) AS risk_score_percentile
)

-- Combine the cohort statistics and the specific patient's info
SELECT 
  cs.mortality_30d_rate,
  cs.cardiac_complication_rate,
  cs.neuro_complication_rate,
  cs.median_survival_days,
  pi.patient_risk_score,
  pi.risk_score_percentile
FROM cohort_stats cs
CROSS JOIN patient_info pi;