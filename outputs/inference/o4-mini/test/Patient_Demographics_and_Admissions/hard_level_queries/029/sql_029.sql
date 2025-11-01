WITH hip_fracture_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
  WHERE
    -- Medicare insurance
    LOWER(a.insurance) LIKE '%medicare%'
    -- Transfer from another hospital
    AND UPPER(a.admission_location) LIKE '%TRANSFER%HOSPITAL%'
    -- Female patients
    AND p.gender = 'F'
    -- Age between 46 and 56
    AND p.anchor_age BETWEEN 46 AND 56
    -- Principal diagnosis (seq_num = 1) of hip fracture (ICD-9 codes starting with 820)
    AND d.seq_num = 1
    AND d.icd_version = 9
    AND d.icd_code LIKE '820%'
),
first_admission_per_subject AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    hip_fracture_adms
)
SELECT
  COUNT(*) AS num_index_admissions
FROM
  first_admission_per_subject
WHERE
  rn = 1;