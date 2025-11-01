WITH stroke_patients AS (
  -- Get male patients aged 46-56 with stroke diagnosis
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND d.icd_code LIKE 'I6%'  -- Stroke ICD-10 codes (I60-I69)
),

first_admissions AS (
  -- Filter to only first admissions
  SELECT
    subject_id,
    hadm_id,
    admittime
  FROM
    stroke_patients
  WHERE
    admission_rank = 1
),

icu_los AS (
  -- Get ICU LOS for first admissions
  SELECT
    i.los
  FROM
    first_admissions fa
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON fa.subject_id = i.subject_id AND fa.hadm_id = i.hadm_id
  WHERE
    i.los > 0  -- Exclude zero or negative LOS
)

-- Calculate IQR (25th, 50th, 75th percentiles)
SELECT
  PERCENTILE_CONT(i.los, 0.25) OVER() AS q1,
  PERCENTILE_CONT(i.los, 0.5) OVER() AS median,
  PERCENTILE_CONT(i.los, 0.75) OVER() AS q3,
  PERCENTILE_CONT(i.los, 0.75) OVER() - PERCENTILE_CONT(i.los, 0.25) OVER() AS iqr
FROM
  icu_los i
LIMIT 1;