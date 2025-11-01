WITH heart_failure_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-9 codes for heart failure (428.xx)
    (icd_version = 9 AND icd_code LIKE '428%')
    OR
    -- ICD-10 codes for heart failure (I50.xx)
    (icd_version = 10 AND icd_code LIKE 'I50%')
),

qualifying_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) as admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN heart_failure_codes hf ON d.icd_code = hf.icd_code AND d.icd_version = hf.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'TRANSFER'
    AND d.seq_num = 1  -- Principal diagnosis
)

SELECT
  COUNT(DISTINCT subject_id) AS number_of_qualifying_patients,
  COUNT(hadm_id) AS number_of_index_admissions
FROM qualifying_admissions
WHERE admission_rank = 1  -- Only count the first qualifying admission per patient;