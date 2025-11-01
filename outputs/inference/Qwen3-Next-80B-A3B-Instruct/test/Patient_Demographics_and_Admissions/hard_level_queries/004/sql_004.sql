WITH qualifying_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.anchor_year,
    LOWER(d.long_title) AS diagnosis_title
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d_icd
    ON a.hadm_id = d_icd.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON d_icd.icd_code = d.icd_code
    AND d_icd.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'TRANSFER FROM HOSP'
    AND d_icd.seq_num = 1
    AND LOWER(d.long_title) LIKE '%osteomyelitis%'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 85 AND 95
),
first_qualifying_admission AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    qualifying_admissions
)
SELECT
  COUNT(*) AS index_admissions_count
FROM
  first_qualifying_admission
WHERE
  rn = 1;