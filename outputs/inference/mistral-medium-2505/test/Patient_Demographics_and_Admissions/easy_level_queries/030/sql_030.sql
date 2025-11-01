WITH
-- Get first admission for each patient
first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Filter for women aged 52-62 with first admission
filtered_patients AS (
  SELECT
    p.subject_id,
    fa.hadm_id,
    fa.admittime,
    fa.dischtime,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    first_admissions fa ON p.subject_id = fa.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND fa.admission_rank = 1
),

-- Identify patients on anticoagulants
anticoagulant_patients AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%warfarin%'
    OR LOWER(drug) LIKE '%heparin%'
    OR LOWER(drug) LIKE '%enoxaparin%'
    OR LOWER(drug) LIKE '%apixaban%'
    OR LOWER(drug) LIKE '%rivaroxaban%'
    OR LOWER(drug) LIKE '%dabigatran%'
    OR LOWER(drug) LIKE '%fondaparinux%'
)

-- Calculate LOS and its standard deviation
SELECT
  STDDEV(DATETIME_DIFF(dischtime, admittime, DAY)) AS los_stddev_days
FROM
  filtered_patients fp
JOIN
  anticoagulant_patients ap ON fp.subject_id = ap.subject_id AND fp.hadm_id = ap.hadm_id;