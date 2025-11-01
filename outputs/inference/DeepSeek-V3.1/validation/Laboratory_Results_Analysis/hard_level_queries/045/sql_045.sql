WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND dd.icd_code LIKE 'J45%'
    AND LOWER(dd.long_title) LIKE '%exacerbation%'
),
labs_72hr AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    le.charttime,
    le.itemid,
    le.valuenum,
    le.value,
    le.flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
),
abnormal_labs AS (
  SELECT 
    subject_id,
    hadm_id,
    -- Count distinct lab events (by itemid and charttime) that are abnormal
    COUNT(DISTINCT CONCAT(CAST(itemid AS STRING), CAST(charttime AS STRING))) AS instability_score
  FROM labs_72hr
  WHERE flag IS NOT NULL AND flag != 'normal'
  GROUP BY subject_id, hadm_id
),
cohort_with_score AS (
  SELECT 
    c.*,
    COALESCE(a.instability_score, 0) AS instability_score
  FROM cohort c
  LEFT JOIN abnormal_labs a
    ON c.hadm_id = a.hadm_id
),
percentile_calc AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100) AS percentiles
  FROM cohort_with_score
),
p90 AS (
  SELECT percentiles[OFFSET(90)] AS p90_score
  FROM percentile_calc
),
top_decile AS (
  SELECT 
    subject_id,
    hadm_id,
    instability_score,
    hospital_expire_flag,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM cohort_with_score
  WHERE instability_score >= (SELECT p90_score FROM p90)
),
cohort_agg AS (
  SELECT 
    'Entire Cohort' AS group_label,
    COUNT(*) AS n_patients,
    AVG(instability_score) AS avg_instability_score,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
    SUM(hospital_expire_flag) AS mortality_count,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS mortality_rate
  FROM cohort_with_score
),
top_decile_agg AS (
  SELECT 
    'Top Decile' AS group_label,
    COUNT(*) AS n_patients,
    AVG(instability_score) AS avg_instability_score,
    AVG(los_days) AS avg_los_days,
    SUM(hospital_expire_flag) AS mortality_count,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS mortality_rate
  FROM top_decile
)
SELECT * FROM cohort_agg
UNION ALL
SELECT * FROM top_decile_agg
ORDER BY group_label;