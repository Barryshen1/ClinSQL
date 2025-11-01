WITH filtered_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND a.insurance = 'Medicare'
),
pneumonia_admissions AS (
  SELECT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.seq_num = 1  -- Principal diagnosis
    AND d.icd_version = 9  -- Assuming ICD-9 is used; adjust as necessary
    AND d.icd_code IN (
      -- ICD-9 codes for pneumonia; this is not an exhaustive list
      '480.0', '480.1', '480.2', '480.3', '480.8', '480.9', 
      '481', '482.0', '482.1', '482.2', '482.3', '482.30', '482.31', '482.32', 
      '482.39', '482.4', '482.40', '482.41', '482.42', '482.49', '482.8', '482.81', 
      '482.82', '482.83', '482.84', '482.89', '482.9', '483.0', '483.1', '483.8', 
      '485', '486', '487.0'
    )
  UNION ALL
  SELECT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.seq_num = 1  -- Principal diagnosis
    AND d.icd_version = 10  -- ICD-10 codes
    AND d.icd_code LIKE 'J09%' OR d.icd_code LIKE 'J10%' OR d.icd_code LIKE 'J11%' 
    OR d.icd_code LIKE 'J12%' OR d.icd_code LIKE 'J13%' OR d.icd_code LIKE 'J14%' 
    OR d.icd_code LIKE 'J15%' OR d.icd_code LIKE 'J16%' OR d.icd_code LIKE 'J17%' 
    OR d.icd_code LIKE 'J18%'
)
SELECT COUNT(*)
FROM filtered_admissions
INNER JOIN pneumonia_admissions
  USING (hadm_id);