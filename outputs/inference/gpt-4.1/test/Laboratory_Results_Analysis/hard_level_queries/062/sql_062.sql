WITH
-- Step 1: Identify sepsis ICD codes (ICD-9 and ICD-10)
sepsis_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-9 sepsis codes
    (icd_version = 9 AND (
      icd_code IN ('99591', '99592', '78552')
      OR icd_code LIKE '038%' -- Septicemia
    ))
    -- ICD-10 sepsis codes
    OR (icd_version = 10 AND (
      icd_code LIKE 'A40%' -- Streptococcal sepsis
      OR icd_code LIKE 'A41%' -- Other sepsis
    ))
),

-- Step 2: Admissions with sepsis
sepsis_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN sepsis_codes s
    ON d.icd_code = s.icd_code AND d.icd_version = s.icd_version
),

-- Step 3: Cohort admissions (female, age 43-53, sepsis)
cohort_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN sepsis_admissions s
    ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
),

-- Step 4: All admissions (for general population stats)
all_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),

-- Step 5: Critical lab event count per admission (cohort)
cohort_lab_events AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    COUNT(le.labevent_id) AS critical_lab_events
  FROM cohort_admissions ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ca.subject_id = le.subject_id
    AND ca.hadm_id = le.hadm_id
    AND le.flag IN ('abnormal', 'critical')
    AND le.charttime >= ca.admittime
    AND le.charttime < TIMESTAMP_ADD(ca.admittime, INTERVAL 72 HOUR)
  GROUP BY ca.subject_id, ca.hadm_id
),

-- Step 6: Critical lab event count per admission (general population)
all_lab_events AS (
  SELECT
    aa.subject_id,
    aa.hadm_id,
    COUNT(le.labevent_id) AS critical_lab_events
  FROM all_admissions aa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON aa.subject_id = le.subject_id
    AND aa.hadm_id = le.hadm_id
    AND le.flag IN ('abnormal', 'critical')
    AND le.charttime >= aa.admittime
    AND le.charttime < TIMESTAMP_ADD(aa.admittime, INTERVAL 72 HOUR)
  GROUP BY aa.subject_id, aa.hadm_id
),

-- Step 7: LOS per admission (cohort)
cohort_los AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    TIMESTAMP_DIFF(ca.dischtime, ca.admittime, HOUR)/24.0 AS los_days,
    ca.hospital_expire_flag
  FROM cohort_admissions ca
),

-- Step 8: LOS per admission (general population)
all_los AS (
  SELECT
    aa.subject_id,
    aa.hadm_id,
    TIMESTAMP_DIFF(aa.dischtime, aa.admittime, HOUR)/24.0 AS los_days,
    aa.hospital_expire_flag
  FROM all_admissions aa
),

-- Step 9: Combine cohort stats
cohort_stats AS (
  SELECT
    COUNT(DISTINCT CONCAT(cl.subject_id, '-', cl.hadm_id)) AS cohort_size,
    APPROX_QUANTILES(cl.critical_lab_events, 4)[OFFSET(1)] AS instability_score_25th_percentile,
    AVG(cl.critical_lab_events) AS mean_instability_score,
    AVG(clo.los_days) AS mean_los,
    AVG(CAST(clo.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM cohort_lab_events cl
  INNER JOIN cohort_los clo
    ON cl.subject_id = clo.subject_id AND cl.hadm_id = clo.hadm_id
),

-- Step 10: Combine general population stats
general_stats AS (
  SELECT
    COUNT(DISTINCT CONCAT(al.subject_id, '-', al.hadm_id)) AS population_size,
    APPROX_QUANTILES(al.critical_lab_events, 4)[OFFSET(1)] AS instability_score_25th_percentile,
    AVG(al.critical_lab_events) AS mean_instability_score,
    AVG(alo.los_days) AS mean_los,
    AVG(CAST(alo.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM all_lab_events al
  INNER JOIN all_los alo
    ON al.subject_id = alo.subject_id AND al.hadm_id = alo.hadm_id
)

-- Final output: Cohort and general stats
SELECT
  'Cohort (Female, Age 43-53, Sepsis)' AS group_name,
  cohort_size AS n_admissions,
  instability_score_25th_percentile AS instability_score_25th_percentile,
  mean_instability_score,
  mean_los,
  mortality_rate
FROM cohort_stats

UNION ALL

SELECT
  'General Population' AS group_name,
  population_size AS n_admissions,
  instability_score_25th_percentile AS instability_score_25th_percentile,
  mean_instability_score,
  mean_los,
  mortality_rate
FROM general_stats
;