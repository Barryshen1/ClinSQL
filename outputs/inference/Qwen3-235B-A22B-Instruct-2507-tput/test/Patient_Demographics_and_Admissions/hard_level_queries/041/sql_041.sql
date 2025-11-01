WITH diagnosis_filter AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%osteomyelitis%'
    AND icd_version = 10
),
admission_with_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.admission_location,
    a.insurance,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) AS age_at_admission,
    di.seq_num,
    di.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE di.icd_version = 10
    AND di.icd_code IN (SELECT icd_code FROM diagnosis_filter)
    AND di.seq_num = 1  -- Principal diagnosis
    AND a.insurance = 'Medicare'
    AND p.gender = 'F'
    AND LOWER(a.admission_location) LIKE '%emergency%'
),
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    age_at_admission
  FROM (
    SELECT
      subject_id,
      hadm_id,
      age_at_admission,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM admission_with_age
  )
  WHERE rn = 1  -- Only the first (index) admission
    AND age_at_admission BETWEEN 80 AND 90
)
SELECT COUNT(*) AS cohort_count
FROM index_admissions;