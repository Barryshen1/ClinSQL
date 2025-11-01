WITH troponin_first AS (
  SELECT 
    labevents.hadm_id,
    labevents.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` labevents
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_labitems
    ON labevents.itemid = d_labitems.itemid
  WHERE d_labitems.label LIKE '%Troponin T%'
    AND labevents.valueuom = 'ng/mL'
    AND labevents.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY labevents.hadm_id ORDER BY labevents.charttime) = 1
)

SELECT 
  COUNT(*) AS total_patients,
  SUM(admissions.hospital_expire_flag) AS deaths,
  SUM(admissions.hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM `physionet-data.mimiciv_3_1_hosp.admissions` admissions
JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
  ON admissions.subject_id = patients.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diagnoses_icd
  ON admissions.hadm_id = diagnoses_icd.hadm_id
  AND diagnoses_icd.seq_num = 1
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd_diagnoses
  ON diagnoses_icd.icd_code = d_icd_diagnoses.icd_code
  AND diagnoses_icd.icd_version = d_icd_diagnoses.icd_version
JOIN troponin_first
  ON admissions.hadm_id = troponin_first.hadm_id
  AND troponin_first.valuenum > 0.04
WHERE 
  patients.gender = 'M'
  AND (patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)) BETWEEN 58 AND 68
  AND (d_icd_diagnoses.long_title LIKE '%chest pain%' OR d_icd_diagnoses.long_title LIKE '%myocardial infarction%');