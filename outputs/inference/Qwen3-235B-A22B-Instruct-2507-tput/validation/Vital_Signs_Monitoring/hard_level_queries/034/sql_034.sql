WITH patient_cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a USING (subject_id)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di USING (hadm_id)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 60 AND 70
    AND d.icd_code IN ('R57.0', 'R57.2')
  GROUP BY p.subject_id, a.hadm_id
  HAVING COUNT(DISTINCT d.icd_code) = 2
),
icu_stays_with_age AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    LEAST(DATETIME_ADD(ie.intime, INTERVAL 48 HOUR), ie.outtime) AS end_48h_or_out,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu`.icustays ie
  INNER JOIN patient_cohort pc ON ie.subject_id = pc.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a USING (hadm_id)
),
vital_params AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE label IN ('Heart Rate', 'Mean Blood Pressure')
),
vital_events_48h AS (
  SELECT 
    ce.stay_id,
    EXTRACT(HOUR FROM DATETIME_DIFF(ce.charttime, ie.intime, SECOND) / 3600) AS hour_offset,
    MAX(CASE WHEN di.label = 'Mean Blood Pressure' AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_lt_65,
    MAX(CASE WHEN di.label = 'Heart Rate' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_gt_100
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN icu_stays_with_age ie ON ce.stay_id = ie.stay_id
  INNER JOIN vital_params di ON ce.itemid = di.itemid
  WHERE ce.charttime >= ie.intime 
    AND ce.charttime < DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id, hour_offset
),
instability_scores AS (
  SELECT 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.hospital_expire_flag,
    COUNT(DISTINCT CASE WHEN ve.map_lt_65 = 1 OR ve.hr_gt_100 = 1 THEN ve.hour_offset END) AS instability_score,
    MAX(CASE WHEN ve.map_lt_65 = 1 THEN 1 ELSE 0 END) AS any_hypotension,
    MAX(CASE WHEN ve.hr_gt_100 = 1 THEN 1 ELSE 0 END) AS any_tachycardia,
    DATETIME_DIFF(ie.outtime, ie.intime, SECOND) / 3600.0 AS los_hrs
  FROM icu_stays_with_age ie
  LEFT JOIN vital_events_48h ve ON ie.stay_id = ve.stay_id
  GROUP BY ie.stay_id, ie.intime, ie.outtime, ie.hospital_expire_flag
),
cohort_quantiles AS (
  SELECT
    APPROX_QUANTILES(instability_score, 1000)[OFFSET(900)] AS p90_score,
    APPROX_QUANTILES(instability_score, 1000)[OFFSET(950)] AS p95_score
  FROM instability_scores
),
summary_data AS (
  SELECT
    'Cohort' AS group_name,
    (SELECT p95_score FROM cohort_quantiles) AS p95_instability_score,
    AVG(CAST(any_hypotension AS FLOAT64)) AS pct_hypotension,
    AVG(CAST(any_tachycardia AS FLOAT64)) AS pct_tachycardia,
    AVG(los_hrs) AS median_los_hrs,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM instability_scores
  UNION ALL
  SELECT
    'Top Decile' AS group_name,
    (SELECT p95_score FROM cohort_quantiles) AS p95_instability_score,
    AVG(CAST(any_hypotension AS FLOAT64)) AS pct_hypotension,
    AVG(CAST(any_tachycardia AS FLOAT64)) AS pct_tachycardia,
    AVG(los_hrs) AS median_los_hrs,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM instability_scores
  CROSS JOIN cohort_quantiles
  WHERE instability_score >= p90_score
)
SELECT * FROM summary_data;