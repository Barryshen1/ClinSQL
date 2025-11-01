WITH cohort_hadms AS (
  SELECT DISTINCT s.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu`.icustays s
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON s.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d ON s.subject_id = d.subject_id AND s.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '415.1%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I26.%')
    )
),
cohort_stays AS (
  SELECT i.*
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN cohort_hadms ch ON i.hadm_id = ch.hadm_id
),
diag_scores AS (
  SELECT 
    cs.stay_id,
    COUNT(DISTINCT le.itemid) AS diag_util_score
  FROM cohort_stays cs
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le 
    ON le.subject_id = cs.subject_id 
    AND le.hadm_id = cs.hadm_id
    AND le.charttime >= cs.intime 
    AND le.charttime < DATETIME_ADD(cs.intime, INTERVAL 1 DAY)
  GROUP BY cs.stay_id
)
SELECT 
  (SELECT APPROX_QUANTILES(diag_util_score, 100)[OFFSET(75)] FROM diag_scores) AS p75th_percentile_diagnostic_utilization_score,
  (SELECT AVG(los) FROM cohort_stays) AS avg_icu_los_cohort_days,
  (SELECT AVG(los) FROM `physionet-data.mimiciv_3_1_icu`.icustays) AS avg_icu_los_general_days,
  (SELECT 1.0 * SUM(CAST(a.hospital_expire_flag AS INT64)) / COUNT(*) 
   FROM cohort_hadms ch 
   INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON ch.hadm_id = a.hadm_id) AS in_hospital_mortality_cohort,
  (SELECT 1.0 * SUM(CAST(a.hospital_expire_flag AS INT64)) / COUNT(*) 
   FROM (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu`.icustays) gh 
   INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON gh.hadm_id = a.hadm_id) AS in_hospital_mortality_general;