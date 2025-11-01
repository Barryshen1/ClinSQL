WITH cohort AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 39 AND 49
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('49391', '49392'))
      OR 
      (d.icd_version = 10 AND d.icd_code IN ('J45901','J45902','J45401','J45402','J45501','J45502'))
    )
),
lab_counts AS (
  SELECT 
    le.hadm_id,
    COUNT(*) AS count_critical
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN cohort c ON le.hadm_id = c.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON le.hadm_id = a.hadm_id
  WHERE 
    le.charttime >= a.admittime
    AND le.charttime < DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
    AND le.flag IS NOT NULL
    AND LOWER(le.flag) LIKE '%critical%'
  GROUP BY le.hadm_id
),
cohort_los_mort AS (
  SELECT 
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cohort c ON a.hadm_id = c.hadm_id
)
SELECT 
  APPROX_QUANTILES(IFNULL(lc.count_critical, 0), 1000)[OFFSET(750)] AS p75_critical_lab_events,
  APPROX_QUANTILES(clm.los_days, 1000)[OFFSET(500)] AS median_los_days,
  AVG(clm.hospital_expire_flag) AS mortality_rate
FROM cohort_los_mort clm
LEFT JOIN lab_counts lc ON clm.hadm_id = lc.hadm_id;