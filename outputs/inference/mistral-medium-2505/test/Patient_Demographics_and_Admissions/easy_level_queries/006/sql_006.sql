WITH sepsis_patients AS (
  -- Identify female patients aged 58-68 with sepsis
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND (
      -- ICD-9 codes for sepsis
      (d.icd_version = 9 AND d.icd_code IN ('995.91', '995.92', '785.52', '995.90'))
      OR
      -- ICD-10 codes for sepsis
      (d.icd_version = 10 AND d.icd_code IN ('R65.20', 'R65.21', 'R65.10', 'R65.11', 'A41.9', 'A40.9'))
    )
),

icu_los AS (
  -- Calculate ICU LOS for sepsis patients
  SELECT
    s.hadm_id,
    s.stay_id,
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    sepsis_patients sp
    ON s.subject_id = sp.subject_id AND s.hadm_id = sp.hadm_id
  WHERE
    s.intime IS NOT NULL
    AND s.outtime IS NOT NULL
    AND s.outtime > s.intime
)

-- Calculate median ICU LOS per encounter
SELECT
  PERCENTILE_CONT(icu_los.los_days, 0.5) OVER() AS median_icu_los_days
FROM
  icu_los
LIMIT 1;