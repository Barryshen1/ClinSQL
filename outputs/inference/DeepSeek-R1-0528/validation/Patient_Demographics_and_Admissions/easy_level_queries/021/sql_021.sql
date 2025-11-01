WITH patient_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' 
    AND anchor_age BETWEEN 83 AND 93
),
first_admission AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN patient_filtered pf 
    ON adm.subject_id = pf.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) = 1
),
pneumonia_admissions AS (
  SELECT DISTINCT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code
    AND diag.icd_version = d.icd_version
  WHERE REGEXP_CONTAINS(d.long_title, r'(?i)\bpneumonia\b')
)
SELECT 
  COUNT(*) AS total_patients,
  SUM(fa.hospital_expire_flag) AS deaths,
  ROUND(100.0 * SUM(fa.hospital_expire_flag) / COUNT(*), 2) AS mortality_percentage
FROM first_admission fa
INNER JOIN pneumonia_admissions pn 
  ON fa.hadm_id = pn.hadm_id;