WITH female_patients AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 58 AND 68
),

admissions_with_diagnoses AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days,
    d1.icd_code AS stroke_code,
    d2.icd_code AS copd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di1 ON a.subject_id = di1.subject_id AND a.hadm_id = di1.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d1 ON di1.icd_code = d1.icd_code AND di1.icd_version = d1.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2 ON a.subject_id = di2.subject_id AND a.hadm_id = di2.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2 ON di2.icd_code = d2.icd_code AND di2.icd_version = d2.icd_version
  WHERE
    -- Hemorrhagic stroke codes (ICD-10: I61.x, ICD-9: 431.x)
    (d1.icd_code LIKE 'I61%' OR d1.icd_code LIKE '431%')
    -- COPD exacerbation codes (ICD-10: J44.1, ICD-9: 491.21)
    AND (d2.icd_code = 'J44.1' OR d2.icd_code = '491.21')
    -- Ensure we have both diagnoses for the same admission
    AND di1.hadm_id = di2.hadm_id
    AND di1.subject_id = di2.subject_id
    -- Exclude cases where admission and discharge times are the same (likely errors)
    AND a.admittime != a.dischtime
)

SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS q1,
  PERCENTILE_CONT(los_days, 0.5) OVER() AS median,
  PERCENTILE_CONT(los_days, 0.75) OVER() AS q3,
  PERCENTILE_CONT(los_days, 0.75) OVER() - PERCENTILE_CONT(los_days, 0.25) OVER() AS iqr
FROM
  admissions_with_diagnoses
LIMIT 1;