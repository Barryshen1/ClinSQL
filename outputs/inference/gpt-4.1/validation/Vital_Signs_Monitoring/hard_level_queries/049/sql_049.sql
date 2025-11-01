WITH sepsis_icd_codes AS (
  -- ICD-9 and ICD-10 codes for sepsis
  SELECT '99591' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '99592', 9 UNION ALL
  SELECT '038', 9 UNION ALL
  SELECT 'A40', 10 UNION ALL
  SELECT 'A41', 10
),
sepsis_patients AS (
  -- Identify ICU stays with sepsis diagnosis
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime, icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  JOIN sepsis_icd_codes s
    ON dx.icd_version = s.icd_version
    AND (
      dx.icd_code = s.icd_code
      OR dx.icd_code LIKE CONCAT(s.icd_code, '%') -- for codes like 038.xx
    )
),
cohort AS (
  -- Restrict to male, age 78-88
  SELECT sp.*, p.gender, p.anchor_age
  FROM sepsis_patients sp
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON sp.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
),
instability_itemids AS (
  -- Find itemids for 'Instability Score'
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%instability score%'
),
instability_scores AS (
  -- Get max instability score in first 24h for each ICU stay
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    MAX(ce.valuenum) AS instability_score
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.hadm_id = ce.hadm_id
    AND c.stay_id = ce.stay_id
  JOIN instability_itemids ii
    ON ce.itemid = ii.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
final_cohort AS (
  -- Add LOS and hospital mortality
  SELECT
    iscore.subject_id,
    iscore.hadm_id,
    iscore.stay_id,
    iscore.instability_score,
    c.los,
    a.hospital_expire_flag
  FROM instability_scores iscore
  JOIN cohort c
    ON iscore.subject_id = c.subject_id
    AND iscore.hadm_id = c.hadm_id
    AND iscore.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON iscore.hadm_id = a.hadm_id
),
percentile_rank AS (
  -- Calculate percentile rank for score 85
  SELECT
    COUNTIF(instability_score <= 85) / CAST(COUNT(*) AS FLOAT64) * 100 AS percentile_rank_85
  FROM final_cohort
),
quartiles AS (
  -- Calculate 75th percentile cutoff
  SELECT
    APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS q4_cutoff
  FROM final_cohort
),
quartile4 AS (
  -- Select quartile 4 patients
  SELECT
    fc.*
  FROM final_cohort fc
  JOIN quartiles q
    ON fc.instability_score >= q.q4_cutoff
)
SELECT
  pr.percentile_rank_85 AS percentile_rank_for_85,
  q.q4_cutoff AS quartile4_cutoff,
  COUNT(*) AS quartile4_n,
  AVG(q4.los) AS quartile4_mean_icu_los,
  AVG(SAFE_CAST(q4.hospital_expire_flag AS FLOAT64)) AS quartile4_hospital_mortality
FROM quartile4 q4
CROSS JOIN percentile_rank pr
CROSS JOIN quartiles q
;