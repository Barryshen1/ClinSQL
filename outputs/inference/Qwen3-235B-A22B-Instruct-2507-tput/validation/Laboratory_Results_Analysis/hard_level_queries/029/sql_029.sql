WITH patients_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admitty
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 50 AND 60
),
hhs_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%hyperosmolar hyperglycemic%'
     OR LOWER(d.long_title) LIKE '%nonketotic hyperosmolar%'
     OR (d.icd_code = 'E11.01' AND d.icd_version = 10)
),
hhs_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_age pa ON a.subject_id = pa.subject_id
  INNER JOIN hhs_diagnoses hhs ON a.hadm_id = hhs.hadm_id
),
lab_instability AS (
  SELECT
    le.hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN hhs_admissions ha ON le.hadm_id = ha.hadm_id
  WHERE le.charttime >= ha.admittime
    AND le.charttime <= DATETIME_ADD(ha.admittime, INTERVAL 48 HOUR)
    AND LOWER(le.flag) = 'abnormal'
  GROUP BY le.hadm_id
),
percentile_75 AS (
  SELECT
    APPROX_QUANTILES(abnormal_lab_count, 1000)[OFFSET(750)] AS p75_score
  FROM lab_instability
),
high_instability_hhs AS (
  SELECT
    ha.hadm_id,
    ha.hospital_expire_flag,
    ha.los_days
  FROM hhs_admissions ha
  INNER JOIN lab_instability li ON ha.hadm_id = li.hadm_id
  CROSS JOIN percentile_75 p
  WHERE li.abnormal_lab_count >= p.p75_score
),
outcomes_high_hhs AS (
  SELECT
    'high_instability_hhs' AS cohort,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(los_days) AS mean_los_days,
    (SELECT 
       AVG(abnormal_labs_per_day)
     FROM (
       SELECT 
         ha.hadm_id,
         COUNT(*) / ha.los_days AS abnormal_labs_per_day
       FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
       INNER JOIN hhs_admissions ha ON le.hadm_id = ha.hadm_id
       INNER JOIN lab_instability li ON ha.hadm_id = li.hadm_id
       CROSS JOIN percentile_75 p
       WHERE li.abnormal_lab_count >= p.p75_score
         AND le.charttime >= ha.admittime
         AND le.charttime <= ha.dischtime
         AND LOWER(le.flag) = 'abnormal'
       GROUP BY ha.hadm_id, ha.los_days
     )
    ) AS critical_lab_rate
  FROM high_instability_hhs
),
general_inpatients AS (
  SELECT
    'general_inpatients' AS cohort,
    AVG(a.hospital_expire_flag) AS mortality_rate,
    AVG(DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS mean_los_days,
    (SELECT 
       AVG(abnormal_labs_per_day)
     FROM (
       SELECT 
         a.hadm_id,
         COUNT(*) / (DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS abnormal_labs_per_day
       FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
       INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
         ON le.hadm_id = a.hadm_id
       WHERE le.charttime >= a.admittime
         AND le.charttime <= a.dischtime
         AND LOWER(le.flag) = 'abnormal'
         AND a.dischtime IS NOT NULL
         AND DATETIME_DIFF(a.dischtime, a.admittime, SECOND) > 0
       GROUP BY a.hadm_id, a.dischtime, a.admittime
     )
    ) AS critical_lab_rate
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
)
SELECT
  '75th_percentile_lab_instability_score' AS metric,
  CAST((SELECT p75_score FROM percentile_75) AS STRING) AS value
UNION ALL
SELECT
  'mortality_rate_high_instability_hhs',
  CAST(mortality_rate AS STRING)
FROM outcomes_high_hhs
UNION ALL
SELECT
  'mean_los_days_high_instability_hhs',
  CAST(mean_los_days AS STRING)
FROM outcomes_high_hhs
UNION ALL
SELECT
  'critical_lab_rate_high_instability_hhs',
  CAST(critical_lab_rate AS STRING)
FROM outcomes_high_hhs
UNION ALL
SELECT
  'critical_lab_rate_general_inpatients',
  CAST(critical_lab_rate AS STRING)
FROM general_inpatients;