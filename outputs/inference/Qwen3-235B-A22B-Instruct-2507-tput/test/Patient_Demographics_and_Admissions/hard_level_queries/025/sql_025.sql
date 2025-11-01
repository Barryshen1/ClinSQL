WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.insurance,
    a.admission_type,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'TRANSFER'
),
heart_failure_diagnoses AS (
  SELECT
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    di.seq_num = 1
    AND LOWER(d.long_title) LIKE '%heart failure%'
),
cohort AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime
  FROM
    patient_admissions pa
  INNER JOIN
    heart_failure_diagnoses hf
  ON
    pa.hadm_id = hf.hadm_id
  WHERE
    pa.age_at_admission >= 65
    AND pa.age_at_admission <= 75
),
index_admissions AS (
  SELECT
    subject_id,
    MIN(admittime) AS first_admittime
  FROM
    cohort
  GROUP BY
    subject_id
)
SELECT
  COUNT(*) AS index_admission_count
FROM
  index_admissions;