WITH
-- Get female patients aged 82-92 at admission
female_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admission_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),

-- Calculate age at admission (approximate)
patient_age_at_admission AS (
  SELECT
    subject_id,
    anchor_age + (admission_year - anchor_year) AS age_at_admission
  FROM
    female_patients
  WHERE
    anchor_age + (admission_year - anchor_year) BETWEEN 82 AND 92
),

-- Get cardiac procedures (ICD-9 codes starting with 35 or 36, or ICD-10 codes starting with 02)
cardiac_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.icd_code,
    p.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    (p.icd_version = 9 AND (p.icd_code LIKE '35%' OR p.icd_code LIKE '36%'))
    OR (p.icd_version = 10 AND p.icd_code LIKE '02%')
),

-- Count distinct cardiac procedures per hospitalization
procedures_per_hadm AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT c.icd_code) AS distinct_cardiac_procedures
  FROM
    cardiac_procedures c
  JOIN
    patient_age_at_admission a
  ON
    c.subject_id = a.subject_id
  GROUP BY
    c.hadm_id
  HAVING
    COUNT(DISTINCT c.icd_code) > 0
)

-- Calculate the 25th percentile of distinct cardiac procedures per hospitalization
SELECT
  PERCENTILE_CONT(distinct_cardiac_procedures, 0.25) OVER() AS percentile_25
FROM
  procedures_per_hadm
LIMIT 1;