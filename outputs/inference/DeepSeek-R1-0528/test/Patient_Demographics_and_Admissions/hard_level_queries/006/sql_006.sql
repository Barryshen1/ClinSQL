WITH principal_dx AS (
  SELECT 
    subject_id, 
    hadm_id, 
    icd_code, 
    icd_version
  FROM (
    SELECT 
      subject_id, 
      hadm_id, 
      icd_code, 
      icd_version,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY seq_num) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  )
  WHERE rn = 1
    AND (
      (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('430', '431', '432'))
      OR
      (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
    )
)

SELECT 
  COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
INNER JOIN principal_dx dx
  ON adm.hadm_id = dx.hadm_id
WHERE 
  pat.gender = 'F'
  AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
  AND adm.insurance = 'Medicare'
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) 
      BETWEEN 36 AND 46;