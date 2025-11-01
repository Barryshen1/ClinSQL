WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.insurance,
    a.admission_location,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
),
admissions_with_age AS (
  SELECT
    subject_id,
    hadm_id,
    insurance,
    admission_location,
    gender,
    -- Calculate age at admission
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM
    index_admissions
  WHERE
    rn = 1  -- Only index admissions
),
pneumonia_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    di.seq_num = 1  -- Principal diagnosis
    AND LOWER(d.long_title) LIKE '%pneumonia%'
)
SELECT
  COUNT(*) AS total_index_admissions
FROM
  admissions_with_age a
JOIN
  pneumonia_diagnoses p
ON
  a.hadm_id = p.hadm_id
WHERE
  a.gender = 'M'
  AND a.insurance = 'Medicare'
  AND (LOWER(a.admission_location) LIKE '%emergency%'
       OR LOWER(a.admission_location) LIKE '%er%')
  AND a.age_at_admission BETWEEN 77 AND 87;