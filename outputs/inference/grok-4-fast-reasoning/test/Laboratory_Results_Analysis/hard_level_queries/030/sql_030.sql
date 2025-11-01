WITH cohort_hadms AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND d.icd_version = 10
    AND d.icd_code LIKE 'J45%'
),
lab_counts_cohort AS (
  SELECT 
    ch.hadm_id,
    COUNT(le.labevent_id) AS critical_count
  FROM cohort_hadms ch
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ch.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = a.hadm_id
    AND le.flag != ''
    AND le.charttime >= a.admittime
    AND le.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY ch.hadm_id
),
all_hadms AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
lab_counts_all AS (
  SELECT 
    ah.hadm_id,
    COUNT(le.labevent_id) AS critical_count
  FROM all_hadms ah
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ah.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = a.hadm_id
    AND le.flag != ''
    AND le.charttime >= a.admittime
    AND le.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY ah.hadm_id
),
cohort_summary AS (
  SELECT 
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS avg_los_days,
    SUM(CAST(a.hospital_expire_flag AS INT64)) * 1.0 / COUNT(*) AS mortality_rate
  FROM cohort_hadms ch
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ch.hadm_id = a.hadm_id
),
cohort_lab_stats AS (
  SELECT 
    APPROX_QUANTILES(critical_count, 4)[OFFSET(3)] AS p75_lab_instability,
    AVG(critical_count) AS avg_critical_cohort
  FROM lab_counts_cohort
),
all_lab_stats AS (
  SELECT 
    AVG(critical_count) AS avg_critical_all
  FROM lab_counts_all
)
SELECT 
  p75_lab_instability,
  avg_critical_cohort,
  avg_critical_all,
  avg_los_days,
  mortality_rate
FROM cohort_lab_stats, all_lab_stats, cohort_summary;