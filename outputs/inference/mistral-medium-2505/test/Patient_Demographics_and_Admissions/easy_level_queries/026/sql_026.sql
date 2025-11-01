WITH
-- Get first admission for each patient
first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Filter for first admissions only
filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    first_admissions a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    a.admission_rank = 1
),

-- Identify CABG procedures
cabg_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    -- ICD-9 codes for CABG
    (p.icd_version = 9 AND p.icd_code LIKE '36.1%')
    OR
    -- ICD-10 codes for CABG
    (p.icd_version = 10 AND p.icd_code LIKE '2A36%')
),

-- Combine all filters
cohort AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.age_at_admission,
    fa.gender,
    fa.hospital_expire_flag
  FROM
    filtered_admissions fa
  JOIN
    cabg_procedures cp
  ON
    fa.subject_id = cp.subject_id AND fa.hadm_id = cp.hadm_id
  WHERE
    fa.gender = 'M'
    AND fa.age_at_admission BETWEEN 48 AND 58
)

-- Calculate 25th percentile of in-hospital mortality
SELECT
  PERCENTILE_CONT(CAST(hospital_expire_flag AS FLOAT64), 0.25) OVER() AS percentile_25_mortality
FROM
  cohort
LIMIT 1;