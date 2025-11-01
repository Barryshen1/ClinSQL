WITH septic_shock_cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND (
      (di.icd_version = 9 AND di.icd_code = '785.52')
      OR (di.icd_version = 10 AND di.icd_code = 'R65.21')
    )
),
chartevents_48h AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.itemid,
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN septic_shock_cohort s
    ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id
  WHERE c.charttime BETWEEN s.admittime AND DATETIME_ADD(s.admittime, INTERVAL 48 HOUR)
    AND c.itemid IN (220210, 220050, 220739)
),
qsofa_flags AS (
  SELECT 
    s.subject_id,
    s.hadm_id,
    MAX(CASE WHEN c.itemid = 220210 AND c.valuenum >= 22 THEN 1 ELSE 0 END) AS rr_flag,
    MAX(CASE WHEN c.itemid = 220050 AND c.valuenum <= 100 THEN 1 ELSE 0 END) AS sbp_flag,
    MAX(CASE WHEN c.itemid = 220739 AND c.valuenum < 15 THEN 1 ELSE 0 END) AS gcs_flag
  FROM septic_shock_cohort s
  LEFT JOIN chartevents_48h c
    ON s.subject_id = c.subject_id AND s.hadm_id = c.hadm_id
  GROUP BY s.subject_id, s.hadm_id
),
qsofa_scores AS (
  SELECT 
    subject_id,
    hadm_id,
    (rr_flag + sbp_flag + gcs_flag) AS qsofa_score
  FROM qsofa_flags
),
lactate_septic AS (
  SELECT 
    COUNTIF(lactate_val > 2) AS abnormal_count,
    COUNT(*) AS total_count
  FROM (
    SELECT 
      s.subject_id,
      s.hadm_id,
      MAX(CASE WHEN le.itemid = 50813 THEN le.valuenum END) AS lactate_val
    FROM septic_shock_cohort s
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON s.subject_id = le.subject_id AND s.hadm_id = le.hadm_id
      AND le.charttime BETWEEN s.admittime AND DATETIME_ADD(s.admittime, INTERVAL 48 HOUR)
    GROUP BY s.subject_id, s.hadm_id
  ) AS subquery
),
lactate_general AS (
  SELECT 
    COUNTIF(lactate_val > 2) AS abnormal_count,
    COUNT(*) AS total_count
  FROM (
    SELECT 
      a.subject_id,
      a.hadm_id,
      MAX(CASE WHEN le.itemid = 50813 THEN le.valuenum END) AS lactate_val
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
      AND le.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
    GROUP BY a.subject_id, a.hadm_id
  ) AS subquery
),
cohort_stats AS (
  SELECT 
    AVG(DATETIME_DIFF(dischtime, admittime, HOUR)/24.0) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM septic_shock_cohort
)
SELECT 
  'qsofa_q1' AS metric,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY qsofa_score) AS value
FROM qsofa_scores
UNION ALL
SELECT 
  'qsofa_median',
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qsofa_score)
FROM qsofa_scores
UNION ALL
SELECT 
  'qsofa_q3',
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY qsofa_score)
FROM qsofa_scores
UNION ALL
SELECT 
  'qsofa_iqr',
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY qsofa_score) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY qsofa_score)
FROM qsofa_scores
UNION ALL
SELECT 
  'lactate_septic',
  abnormal_count / total_count
FROM lactate_septic
UNION ALL
SELECT 
  'lactate_general',
  abnormal_count / total_count
FROM lactate_general
UNION ALL
SELECT 
  'los',
  avg_los
FROM cohort_stats
UNION ALL
SELECT 
  'mortality',
  mortality_rate
FROM cohort_stats;