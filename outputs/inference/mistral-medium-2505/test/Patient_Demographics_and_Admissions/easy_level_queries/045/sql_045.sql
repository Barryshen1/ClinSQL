WITH
-- Filter males aged 51-61
male_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),

-- Get first admission per patient
first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    male_patients p ON a.subject_id = p.subject_id
),

-- Filter admissions with pneumonia diagnosis
pneumonia_admissions AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime
  FROM
    first_admissions fa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON fa.hadm_id = di.hadm_id
  WHERE
    fa.admission_rank = 1  -- First admission
    AND (
      -- ICD-9 code for pneumonia
      (di.icd_version = 9 AND di.icd_code LIKE '486%')
      OR
      -- ICD-10 code for pneumonia
      (di.icd_version = 10 AND di.icd_code LIKE 'J18.9%')
    )
),

-- Get ICU stays for these admissions and calculate LOS
icu_los AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    TIMESTAMP_DIFF(i.outtime, i.intime, DAY) AS icu_los_days
  FROM
    pneumonia_admissions pa
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON pa.hadm_id = i.hadm_id
)

-- Calculate 25th percentile of ICU LOS
SELECT
  PERCENTILE_CONT(icu_los_days, 0.25) OVER() AS percentile_25_icu_los_days
FROM
  icu_los
LIMIT 1;