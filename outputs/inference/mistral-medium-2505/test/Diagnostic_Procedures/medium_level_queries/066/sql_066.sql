WITH
-- Get female patients aged 88-98
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 88 AND 98
),

-- Get patients with asthma diagnoses
asthma_patients AS (
  SELECT DISTINCT
    p.subject_id
  FROM
    female_patients p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    -- ICD-10 codes for asthma (J45.*)
    (d.icd_version = '10' AND d.icd_code LIKE 'J45%')
    -- Or ICD-9 codes for asthma (493.*)
    OR (d.icd_version = '9' AND d.icd_code LIKE '493%')
),

-- Get admissions with duration categories
admissions_with_duration AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS admission_duration_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS duration_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    asthma_patients ap
    ON a.subject_id = ap.subject_id
  WHERE
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Count procedures per admission
procedures_per_admission AS (
  SELECT
    a.hadm_id,
    a.duration_category,
    COUNT(DISTINCT p.icd_code) AS procedure_count
  FROM
    admissions_with_duration a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON CAST(a.hadm_id AS INT64) = CAST(p.hadm_id AS INT64)
  WHERE
    a.duration_category IS NOT NULL
  GROUP BY
    a.hadm_id, a.duration_category
)

-- Calculate percentiles
SELECT
  duration_category,
  APPROX_QUANTILES(procedure_count, 4)[OFFSET(1)] AS percentile_25,
  APPROX_QUANTILES(procedure_count, 4)[OFFSET(2)] AS percentile_50,
  APPROX_QUANTILES(procedure_count, 4)[OFFSET(3)] AS percentile_75
FROM
  procedures_per_admission
GROUP BY
  duration_category
ORDER BY
  duration_category;