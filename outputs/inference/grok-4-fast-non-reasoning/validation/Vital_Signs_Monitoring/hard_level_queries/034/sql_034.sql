WITH patients_female_age AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 60 AND 70
),
mixed_shock_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON diag.hadm_id = adm.hadm_id
  WHERE (
    -- Cardiogenic shock
    (diag.icd_version = '9' AND diag.icd_code = '785.51') OR
    (diag.icd_version = '10' AND diag.icd_code IN ('I97.1', 'I97.12', 'I97.13', 'I97.19'))
  ) OR (
    -- Septic shock
    (diag.icd_version = '9' AND diag.icd_code = '785.52') OR
    (diag.icd_version = '10' AND diag.icd_code = 'R65.2')
  )
),
first_icustays AS (
  SELECT subject_id, hadm_id, stay_id, first_careunit, intime, outtime, los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  WHERE subject_id IN (SELECT subject_id FROM patients_female_age)
    AND hadm_id IN (SELECT hadm_id FROM mixed_shock_hadms)
    AND los >= 0
  QUALIFY ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) = 1
),
vitals_flags AS (
  SELECT 
    fis.subject_id, fis.stay_id, fis.intime,
    LOGICAL_OR(
      CASE WHEN ce.itemid = 220052 AND ce.valuenum < 65 THEN TRUE ELSE FALSE END
    ) OVER (PARTITION BY fis.stay_id) AS hypotension_flag,
    LOGICAL_OR(
      CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN TRUE ELSE FALSE END
    ) OVER (PARTITION BY fis.stay_id) AS tachycardia_flag
  FROM first_icustays fis
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON fis.subject_id = ce.subject_id 
    AND fis.stay_id = ce.stay_id
    AND ce.charttime BETWEEN fis.intime AND fis.intime + INTERVAL 48 HOUR
    AND ce.valuenum IS NOT NULL
),
cohort_with_scores AS (
  SELECT 
    fis.stay_id, fis.los,
    adm.hospital_expire_flag,
    COALESCE(vf.hypotension_flag, FALSE) AS hyp_flag,
    COALESCE(vf.tachycardia_flag, FALSE) AS tach_flag,
    (CAST(COALESCE(vf.hypotension_flag, FALSE) AS INT64) + 
     CAST(COALESCE(vf.tachycardia_flag, FALSE) AS INT64)) / 2.0 AS instability_score
  FROM first_icustays fis
  LEFT JOIN vitals_flags vf ON fis.stay_id = vf.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON fis.hadm_id = adm.hadm_id
),
stats AS (
  SELECT 
    instability_score,
    hyp_flag,
    tach_flag,
    los / 24.0 AS los_days,
    hospital_expire_flag,
    PERCENTILE_CONT(0.95, instability_score) OVER() AS cohort_95th_instability,
    PERCENTILE_CONT(0.9, instability_score) OVER() AS top_decile_threshold
  FROM cohort_with_scores
)
SELECT 
  -- Cohort 95th percentile instability
  cohort_95th_instability AS cohort_95th_instability,
  
  -- Top decile threshold
  top_decile_threshold AS top_decile_threshold,
  
  -- Hypotension %
  100.0 * AVG(CAST(CASE WHEN instability_score >= top_decile_threshold THEN hyp_flag ELSE FALSE END AS FLOAT64)) AS top_decile_hypotension_pct,
  100.0 * AVG(CAST(hyp_flag AS FLOAT64)) AS cohort_hypotension_pct,
  
  -- Tachycardia %
  100.0 * AVG(CAST(CASE WHEN instability_score >= top_decile_threshold THEN tach_flag ELSE FALSE END AS FLOAT64)) AS top_decile_tachycardia_pct,
  100.0 * AVG(CAST(tach_flag AS FLOAT64)) AS cohort_tachycardia_pct,
  
  -- ICU LOS (median days)
  PERCENTILE_CONT(0.5, CASE WHEN instability_score >= top_decile_threshold THEN los_days END) AS top_decile_icu_los_median,
  PERCENTILE_CONT(0.5, los_days) AS cohort_icu_los_median,
  
  -- Mortality %
  100.0 * AVG(CAST(CASE WHEN instability_score >= top_decile_threshold THEN hospital_expire_flag ELSE 0 END AS FLOAT64)) AS top_decile_mortality_pct,
  100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)) AS cohort_mortality_pct
  
FROM stats;