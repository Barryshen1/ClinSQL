WITH patient_ages AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS adm_year,
    (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
),
diagnosis_filtered AS (
  SELECT
    di.hadm_id,
    STRING_AGG(CAST(di.icd_code AS STRING), ', ') AS icd_codes
  FROM
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  GROUP BY
    di.hadm_id
  HAVING
    -- Check for hemorrhagic stroke: ICD-9 431 or ICD-10 I61.*
    (SUM(CASE WHEN di.icd_version = 9 AND di.icd_code = '431' THEN 1
              WHEN di.icd_version = 10 AND di.icd_code LIKE 'I61%' THEN 1
              ELSE 0 END) > 0)
    AND
    -- Check for COPD exacerbation: ICD-9 491.21 or ICD-10 J44.1
    (SUM(CASE WHEN di.icd_version = 9 AND di.icd_code = '491.21' THEN 1
              WHEN di.icd_version = 10 AND di.icd_code = 'J44.1' THEN 1
              ELSE 0 END) > 0)
),
eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    pa.age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN
    diagnosis_filtered df
  ON
    a.hadm_id = df.hadm_id
  JOIN
    patient_ages pa
  ON
    a.subject_id = pa.subject_id
  WHERE
    pa.age_at_admission BETWEEN 58 AND 68
    AND a.dischtime IS NOT NULL
),
los_calc AS (
  SELECT
    hadm_id,
    (DATETIME_DIFF(dischtime, admittime, SECOND) / (24 * 3600.0)) AS los_days
  FROM
    eligible_admissions
)
SELECT
  PERCENTILE_CONT(los_days, 0.75) OVER() - PERCENTILE_CONT(los_days, 0.25) OVER() AS iqr_los
FROM
  los_calc
LIMIT 1;