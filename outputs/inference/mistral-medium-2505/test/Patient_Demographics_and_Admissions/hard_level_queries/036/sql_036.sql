WITH
-- Calculate age at admission for each patient
patient_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.insurance,
    a.admission_type,
    -- Calculate age at admission: anchor_age + (YEAR(admittime) - anchor_year)
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.anchor_year IS NOT NULL
),

-- Filter for index admissions (first admission per patient)
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    gender,
    age_at_admission,
    insurance,
    admission_type,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM
    patient_age
),

-- Filter for acute pancreatitis diagnoses
acute_pancreatitis AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.seq_num,
    d.icd_code,
    d.icd_version,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    -- ICD-10 codes for acute pancreatitis (K85.*)
    (d.icd_version = 10 AND d.icd_code LIKE 'K85.%')
    OR
    -- ICD-9 code for acute pancreatitis (577.0)
    (d.icd_version = 9 AND d.icd_code = '577.0')
)

-- Final query to count the cohort
SELECT
  COUNT(DISTINCT ia.hadm_id) AS total_admissions
FROM
  index_admissions ia
JOIN
  acute_pancreatitis ap
ON
  ia.subject_id = ap.subject_id AND ia.hadm_id = ap.hadm_id
WHERE
  ia.gender = 'F'
  AND ia.age_at_admission BETWEEN 72 AND 82
  AND ia.insurance = 'Medicare'
  AND ia.admission_type = 'EMERGENCY'
  AND ap.seq_num = 1  -- Principal diagnosis
  AND ia.admission_rank = 1  -- Index admission
;