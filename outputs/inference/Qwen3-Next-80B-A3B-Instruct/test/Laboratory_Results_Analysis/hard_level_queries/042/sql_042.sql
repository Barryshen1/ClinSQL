WITH ich_cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND LOWER(dicd.long_title) LIKE '%intracerebral%hemorrhage%'
),

all_cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),

lab_abnormal_48h_ich AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT le.itemid) AS instability_score
  FROM ich_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON c.hadm_id = le.hadm_id
  WHERE le.charttime >= c.admittime
    AND le.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.flag = 'abnormal'
  GROUP BY c.hadm_id
),

lab_abnormal_48h_all AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT le.itemid) AS instability_score
  FROM all_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON c.hadm_id = le.hadm_id
  WHERE le.charttime >= c.admittime
    AND le.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.flag = 'abnormal'
  GROUP BY c.hadm_id
),

cohort_with_scores AS (
  SELECT 
    'ICH' AS cohort,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COALESCE(l.instability_score, 0) AS instability_score
  FROM ich_cohort c
  LEFT JOIN lab_abnormal_48h_ich l ON c.hadm_id = l.hadm_id

  UNION ALL

  SELECT 
    'All' AS cohort,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COALESCE(l.instability_score, 0) AS instability_score
  FROM all_cohort c
  LEFT JOIN lab_abnormal_48h_all l ON c.hadm_id = l.hadm_id
),

quartiles AS (
  SELECT 
    cohort,
    instability_score,
    hospital_expire_flag,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    NTILE(4) OVER (PARTITION BY cohort ORDER BY instability_score) AS quartile
  FROM cohort_with_scores
)

SELECT 
  cohort,
  quartile,
  COUNT(*) AS count,
  AVG(los_days) AS mean_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM quartiles
GROUP BY cohort, quartile
ORDER BY cohort, quartile;