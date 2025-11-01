WITH
-- Get index admissions (first admission for each patient)
index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
),

-- Filter for female Medicare patients aged 85-95 at admission
filtered_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.insurance,
    a.admission_location,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    index_admissions ia ON p.subject_id = ia.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id AND ia.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND ia.admission_rank = 1  -- Index admission
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 85 AND 95
    AND a.admission_location LIKE '%TRANSFER%'
),

-- Get principal diagnosis (seq_num = 1) and join with ICD descriptions
principal_diagnoses AS (
  SELECT
    fp.subject_id,
    fp.hadm_id,
    d.icd_code,
    di.long_title
  FROM
    filtered_patients fp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON fp.subject_id = d.subject_id AND fp.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.seq_num = 1  -- Principal diagnosis
    AND LOWER(di.long_title) LIKE '%osteomyelitis%'
)

-- Count the number of index admissions meeting all criteria
SELECT
  COUNT(DISTINCT pd.subject_id) AS num_patients
FROM
  principal_diagnoses pd;