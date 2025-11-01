WITH cohort_admissions AS (
  -- Define cohort: female, age 78–88, acute ischemic stroke admissions
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    -- ICD-10 acute ischemic stroke codes I63.x
    AND dd.icd_code LIKE 'I63%'
),
cohort_lab_counts AS (
  -- Count critical lab events in first 72h for each cohort admission
  SELECT
    ca.hadm_id,
    COUNT(*) AS crit_events_72h
  FROM
    cohort_admissions ca
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON ca.hadm_id = le.hadm_id
    -- restrict to first 72h
    AND le.charttime BETWEEN ca.admittime
                        AND DATETIME_ADD(ca.admittime, INTERVAL 72 HOUR)
    -- numeric results only
    AND le.valuenum IS NOT NULL
    -- outside reference range
    AND (
      le.valuenum < le.ref_range_lower
      OR le.valuenum > le.ref_range_upper
    )
  GROUP BY
    ca.hadm_id
),
general_lab_counts AS (
  -- Count critical lab events in first 72h for ALL admissions
  SELECT
    a.hadm_id,
    COUNT(*) AS crit_events_72h
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON a.hadm_id = le.hadm_id
    AND le.charttime BETWEEN a.admittime
                        AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND (
      le.valuenum < le.ref_range_lower
      OR le.valuenum > le.ref_range_upper
    )
  GROUP BY
    a.hadm_id
)
SELECT
  -- Cohort metrics
  MIN(clc.crit_events_72h)                             AS cohort_min_instability_score,
  AVG(clc.crit_events_72h)                             AS cohort_avg_crit_events_72h,
  AVG(ca.los_days)                                      AS cohort_avg_los_days,
  -- mortality rate: sum(flag)/count
  SAFE_DIVIDE(
    SUM(ca.hospital_expire_flag),
    COUNT(*) 
  )                                                     AS cohort_mortality_rate,
  -- General inpatient comparison
  (SELECT AVG(crit_events_72h) FROM general_lab_counts) AS general_avg_crit_events_72h
FROM
  cohort_admissions ca
  LEFT JOIN cohort_lab_counts clc
    ON ca.hadm_id = clc.hadm_id;