WITH septic_shock_patients AS (
  SELECT
    p.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND d.icd_code = '785.52'  -- Corrected to ICD-9-CM code for septic shock
    AND d.icd_version = 9
),
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN septic_shock_patients s
    ON i.subject_id = s.subject_id
    AND i.hadm_id = s.hadm_id
),
instability_measurements AS (
  SELECT
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN icu_stays i
    ON c.subject_id = i.subject_id
    AND c.hadm_id = i.hadm_id
    AND c.stay_id = i.stay_id
  WHERE
    c.itemid = 227489
    AND c.charttime BETWEEN i.intime AND i.intime + INTERVAL 48 HOUR
    AND c.valuenum IS NOT NULL
),
instability_quartiles AS (
  SELECT
    APPROX_QUANTILES(valuenum, 4) AS quartiles
  FROM instability_measurements
),
instability_stats AS (
  SELECT
    quartiles[OFFSET(1)] AS Q1,
    quartiles[OFFSET(2)] AS median,
    quartiles[OFFSET(3)] AS Q3,
    quartiles[OFFSET(3)] - quartiles[OFFSET(1)] AS IQR
  FROM instability_quartiles
),
-- For abnormal labs in septic shock cohort
septic_labevents AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.labevent_id,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper,
    CASE
      WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1
      ELSE 0
    END AS abnormal
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  INNER JOIN septic_shock_patients s
    ON l.subject_id = s.subject_id
    AND l.hadm_id = s.hadm_id
  WHERE
    (d.label LIKE '%creatinine%' 
     OR d.label LIKE '%lactate%'
     OR d.label LIKE '%white blood cell%' 
     OR d.label LIKE '%wbc%')
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),
septic_abnormal_per_patient AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    COUNT(l.labevent_id) AS total_labs,
    COALESCE(SUM(l.abnormal), 0) AS abnormal_count  -- Handle NULLs
  FROM septic_shock_patients s
  LEFT JOIN septic_labevents l
    ON s.subject_id = l.subject_id
    AND s.hadm_id = l.hadm_id
  GROUP BY s.subject_id, s.hadm_id
),
septic_avg_abnormal AS (
  SELECT
    AVG(abnormal_count) AS avg_abnormal_per_patient
  FROM septic_abnormal_per_patient
),
-- For general inpatients (all admissions, all ages, all genders)
general_labevents AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.labevent_id,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper,
    CASE
      WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1
      ELSE 0
    END AS abnormal
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON l.subject_id = a.subject_id
    AND l.hadm_id = a.hadm_id
  WHERE
    (d.label LIKE '%creatinine%' 
     OR d.label LIKE '%lactate%'
     OR d.label LIKE '%white blood cell%' 
     OR d.label LIKE '%wbc%')
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),
general_abnormal_per_patient AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(l.labevent_id) AS total_labs,
    COALESCE(SUM(l.abnormal), 0) AS abnormal_count  -- Handle NULLs
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN general_labevents l
    ON a.subject_id = l.subject_id
    AND a.hadm_id = l.hadm_id
  GROUP BY a.subject_id, a.hadm_id
),
general_avg_abnormal AS (
  SELECT
    AVG(abnormal_count) AS avg_abnormal_per_patient
  FROM general_abnormal_per_patient
),
-- For LOS and mortality in septic shock cohort
los_mortality AS (
  SELECT
    AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS avg_los,  -- Fixed function name
    AVG(a.hospital_expire_flag) AS mortality_rate
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN septic_shock_patients s
    ON a.hadm_id = s.hadm_id
)
-- Combine results
SELECT
  'instability_score' AS metric_type,
  'Q1' AS metric_name,
  instability_stats.Q1 AS value
FROM instability_stats
UNION ALL
SELECT
  'instability_score',
  'median',
  instability_stats.median
FROM instability_stats
UNION ALL
SELECT
  'instability_score',
  'Q3',
  instability_stats.Q3
FROM instability_stats
UNION ALL
SELECT
  'instability_score',
  'IQR',
  instability_stats.IQR
FROM instability_stats
UNION ALL
SELECT
  'abnormal_labs',
  'septic_avg_abnormal_per_patient',
  septic_avg_abnormal.avg_abnormal_per_patient
FROM septic_avg_abnormal
UNION ALL
SELECT
  'abnormal_labs',
  'general_avg_abnormal_per_patient',
  general_avg_abnormal.avg_abnormal_per_patient
FROM general_avg_abnormal
UNION ALL
SELECT
  'los_mortality',
  'avg_los_days',
  los_mortality.avg_los
FROM los_mortality
UNION ALL
SELECT
  'los_mortality',
  'mortality_rate',
  los_mortality.mortality_rate
FROM los_mortality;