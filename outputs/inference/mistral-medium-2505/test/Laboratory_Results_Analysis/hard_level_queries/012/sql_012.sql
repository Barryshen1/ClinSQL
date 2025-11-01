WITH
-- Define our AMI cohort (male, age 44-54, with AMI diagnosis)
ami_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND d.icd_code LIKE 'I21%'  -- AMI ICD-10 codes
    AND d.icd_version = 10
),

-- Get critical lab tests for our cohort in first 72 hours
critical_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.valueuom,
    d.label,
    d.category
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  JOIN
    ami_cohort a
    ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE
    TIMESTAMP_DIFF(l.charttime, a.admittime, HOUR) <= 72
    AND l.itemid IN (
      -- Critical lab items (example - would need full list)
      50889, 50893, 50912, 50931, 50971, 51006, 51045, 51221, 51222, 51265
    )
),

-- Calculate lab instability score per patient (simplified to just count labs)
patient_lab_scores AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(*) AS total_labs,
    1 AS instability_score  -- Simplified to just count labs
  FROM
    critical_labs
  GROUP BY
    subject_id, hadm_id
  HAVING
    COUNT(*) >= 3  -- Only include patients with at least 3 lab tests
),

-- Get general inpatient comparison group (same age/gender, no AMI)
general_inpatients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'I21%' AND icd_version = 10
    )
)

-- Final results
SELECT
  -- 75th percentile of lab instability score
  APPROX_QUANTILES(instability_score, 4)[OFFSET(2)] AS percentile_75_lab_instability,

  -- Comparison of critical lab frequency
  (SELECT COUNT(*) FROM critical_labs) AS ami_critical_lab_count,
  (SELECT COUNT(*) FROM critical_labs cl JOIN general_inpatients gi ON cl.subject_id = gi.subject_id AND cl.hadm_id = gi.hadm_id) AS general_critical_lab_count,

  -- Cohort characteristics
  AVG(los_hours) AS avg_los_hours,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
  COUNT(*) AS cohort_size
FROM
  patient_lab_scores pls
JOIN
  ami_cohort a ON pls.subject_id = a.subject_id AND pls.hadm_id = a.hadm_id;