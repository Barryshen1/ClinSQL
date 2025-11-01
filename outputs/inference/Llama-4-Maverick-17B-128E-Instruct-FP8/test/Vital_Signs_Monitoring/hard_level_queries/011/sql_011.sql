WITH 
filtered_patients AS (
  SELECT p.subject_id, p.gender, p.anchor_age, icu.hadm_id, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 55 AND 65
),
pneumonia_patients AS (
  SELECT DISTINCT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE d_diag.long_title LIKE '%Pneumonia%' AND diag.hadm_id IN (SELECT hadm_id FROM filtered_patients)
),
instability_scores AS (
  SELECT fp.stay_id, AVG(ce.valuenum) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN filtered_patients fp ON ce.stay_id = fp.stay_id
  WHERE ce.itemid = 220052  
  AND ce.charttime BETWEEN fp.intime AND TIMESTAMP_ADD(fp.intime, INTERVAL 24 HOUR)
  AND fp.hadm_id IN (SELECT hadm_id FROM pneumonia_patients)
  GROUP BY fp.stay_id
),
percentile_calc AS (
  SELECT 
    instability_score,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile_rank
  FROM instability_scores
)
SELECT 
  (SELECT percentile_rank FROM percentile_calc WHERE instability_score <= 60 ORDER BY instability_score DESC LIMIT 1) AS percentile_of_score_60,
  AVG(icu.los) AS avg_icu_los,
  SUM(CASE WHEN icu.outtime IS NULL THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
JOIN instability_scores isc ON icu.stay_id = isc.stay_id
WHERE isc.instability_score >= (SELECT instability_score FROM percentile_calc WHERE percentile_rank >= 0.9 LIMIT 1);