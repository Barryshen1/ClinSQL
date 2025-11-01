WITH cardiac_arrest_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%cardiac arrest%'
     OR (icd_version = 9 AND icd_code = '4275')
     OR (icd_version = 10 AND icd_code IN ('I460', 'I461', 'I462', 'I468', 'I469'))
),
cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        WHERE diag.hadm_id = a.hadm_id
          AND diag.icd_code = cac.icd_code
          AND diag.icd_version = cac.icd_version
      ) THEN 1 
      ELSE 0 
    END AS has_cardiac_arrest
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  CROSS JOIN cardiac_arrest_codes cac
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admittime IS NOT NULL
),
lab_abnormal_counts AS (
  SELECT 
    c.hadm_id,
    c.has_cardiac_arrest,
    c.los_days,
    c.hospital_expire_flag,
    COUNT(CASE WHEN le.flag = 'abnormal' THEN 1 END) AS abnormal_lab_count_48h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.charttime >= c.admittime
    AND le.charttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.hadm_id, c.has_cardiac_arrest, c.los_days, c.hospital_expire_flag
),
summary_stats AS (
  SELECT
    has_cardiac_arrest,
    APPROX_QUANTILES(abnormal_lab_count_48h, 1000)[OFFSET(250)] AS q1_abnormal_labs,
    APPROX_QUANTILES(abnormal_lab_count_48h, 1000)[OFFSET(500)] AS median_abnormal_labs,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS median_los_days,
    AVG(hospital_expire_flag) AS mortality_rate,
    COUNT(*) AS cohort_size
  FROM lab_abnormal_counts
  GROUP BY has_cardiac_arrest
)
SELECT
  has_cardiac_arrest,
  q1_abnormal_labs,
  median_abnormal_labs,
  median_los_days,
  mortality_rate,
  cohort_size
FROM summary_stats
ORDER BY has_cardiac_arrest;