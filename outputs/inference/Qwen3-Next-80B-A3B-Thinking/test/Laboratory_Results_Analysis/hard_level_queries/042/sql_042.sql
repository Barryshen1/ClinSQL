WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND (
      (di.icd_version = 9 AND di.icd_code = '431')
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I61%')
    )
),

lab_abnormal AS (
  SELECT 
    l.subject_id, 
    l.hadm_id, 
    l.itemid
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN cohort c 
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE l.charttime BETWEEN c.admittime AND c.admittime + INTERVAL '48' HOUR
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
),

instability_score AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COUNT(DISTINCT la.itemid) AS instability_score,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM cohort c
  LEFT JOIN lab_abnormal la 
    ON c.subject_id = la.subject_id AND c.hadm_id = la.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),

quartiles AS (
  SELECT 
    NTILE(4) OVER (ORDER BY instability_score) AS quartile,
    los_days,
    hospital_expire_flag
  FROM instability_score
),

quartile_stats AS (
  SELECT 
    quartile,
    COUNT(*) AS count,
    AVG(los_days) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM quartiles
  GROUP BY quartile
),

overall_stats AS (
  SELECT 
    'Overall' AS quartile,
    COUNT(*) AS count,
    AVG(los_days) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM instability_score
)

SELECT * FROM quartile_stats
UNION ALL
SELECT * FROM overall_stats;