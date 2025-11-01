WITH acute_pancreatitis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    -- Female
    p.gender = 'F'
    -- Age 70-80 at anchor admission
    AND p.anchor_age BETWEEN 70 AND 80
    -- Medicare insurance
    AND a.insurance = 'Medicare'
    -- Admitted from ED (common values: 'EMERGENCY ROOM', 'EMERGENCY DEPARTMENT', etc.)
    AND (
      LOWER(a.admission_location) LIKE '%emergency%'
      OR LOWER(a.admission_location) LIKE '%ed%'
    )
    -- Principal diagnosis (seq_num = 1)
    AND d.seq_num = 1
    -- Acute pancreatitis ICD codes
    AND (
      -- ICD-10 codes
      (d.icd_version = 10 AND (
        d.icd_code = 'K85'
        OR d.icd_code LIKE 'K850%'
        OR d.icd_code LIKE 'K851%'
        OR d.icd_code LIKE 'K852%'
        OR d.icd_code LIKE 'K853%'
        OR d.icd_code LIKE 'K858%'
        OR d.icd_code LIKE 'K859%'
      ))
      -- ICD-9 code
      OR (d.icd_version = 9 AND d.icd_code = '5770')
    )
)

, index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
  FROM
    acute_pancreatitis_admissions
)

SELECT
  COUNT(*) AS num_index_admissions
FROM
  index_admissions
WHERE
  rn = 1;