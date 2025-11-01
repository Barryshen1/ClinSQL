WITH patients_f AS (
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 52 AND 62
),
admissions_f AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_f p ON a.subject_id = p.subject_id
),
ca_diagnoses AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '427.5%')
     OR (icd_version = 10 AND icd_code LIKE 'I46%')
),
cohort AS (
  SELECT a.*
  FROM admissions_f a
  INNER JOIN ca_diagnoses d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
),
general AS (
  SELECT * FROM admissions_f
),
lab_abnormal AS (
  SELECT le.hadm_id, COUNT(*) AS num_abnormal
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN admissions_f a ON le.hadm_id = a.hadm_id
  WHERE le.charttime >= a.admittime
    AND le.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY le.hadm_id
),
cohort_scores AS (
  SELECT 
    c.hadm_id, 
    COALESCE(l.num_abnormal, 0) AS instability_score,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN lab_abnormal l ON c.hadm_id = l.hadm_id
),
general_scores AS (
  SELECT 
    g.hadm_id, 
    COALESCE(l.num_abnormal, 0) AS instability_score
  FROM general g
  LEFT JOIN lab_abnormal l ON g.hadm_id = l.hadm_id
),
cohort_stats AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS q1_instability,
    APPROX_QUANTILES(instability_score, 4)[OFFSET(2)] AS median_instability,
    AVG(instability_score) AS mean_instability_cohort,
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct
  FROM cohort_scores
),
general_stats AS (
  SELECT AVG(instability_score) AS mean_instability_general
  FROM general_scores
)
SELECT 
  q1_instability,
  median_instability,
  mean_instability_cohort,
  mean_instability_general,
  median_los_days,
  mortality_pct
FROM cohort_stats
CROSS JOIN general_stats;