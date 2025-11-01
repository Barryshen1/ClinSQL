WITH admission_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.admission_location,
    a.insurance,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admission_location,
    insurance,
    gender,
    age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_order
  FROM admission_age
),
acute_pancreatitis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%acute pancreatitis%'
),
filtered_index AS (
  SELECT ia.*
  FROM index_admissions ia
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ia.hadm_id = di.hadm_id
  JOIN acute_pancreatitis_codes apc
    ON di.icd_code = apc.icd_code
  WHERE
    ia.admission_order = 1
    AND ia.gender = 'F'
    AND ia.age_at_admission BETWEEN 70 AND 80
    AND LOWER(ia.admission_location) IN ('emergency department', 'ed')
    AND LOWER(ia.insurance) = 'medicare'
    AND di.seq_num = 1  -- principal diagnosis
)
SELECT COUNT(*) AS total_index_admissions
FROM filtered_index;