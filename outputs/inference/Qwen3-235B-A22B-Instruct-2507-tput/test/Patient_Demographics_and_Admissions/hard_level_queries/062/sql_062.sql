WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.admission_location,
    a.insurance,
    di.seq_num,
    di.icd_code,
    di.icd_version,
    d_diag.long_title,
    -- Calculate age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
    ON di.icd_code = d_diag.icd_code AND di.icd_version = d_diag.icd_version
  WHERE
    p.gender = 'F'
    AND LOWER(a.admission_location) LIKE '%emergency%'
    AND LOWER(a.insurance) = 'medicare'
    AND di.seq_num = 1  -- Principal diagnosis
    AND LOWER(d_diag.long_title) = 'acute cholecystitis'
),
ranked_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    patient_admissions
  WHERE
    age_at_admission BETWEEN 38 AND 48
)
SELECT
  COUNT(*) AS total_index_admissions
FROM
  ranked_admissions
WHERE
  rn = 1;