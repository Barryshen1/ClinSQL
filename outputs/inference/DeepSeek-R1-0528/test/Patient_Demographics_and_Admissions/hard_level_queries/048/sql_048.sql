SELECT
  COUNT(DISTINCT adm.hadm_id) AS num_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON p.subject_id = adm.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON adm.hadm_id = diag.hadm_id
  AND adm.subject_id = diag.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
  ON diag.icd_code = d_icd.icd_code
  AND diag.icd_version = d_icd.icd_version
WHERE
  p.gender = 'F'
  AND adm.admission_location = 'EMERGENCY ROOM ADMISSION'
  AND adm.insurance = 'Medicare'
  AND diag.seq_num = 1  -- Principal diagnosis
  AND LOWER(d_icd.long_title) LIKE '%pneumonia%'  -- Case-insensitive match
  AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) 
      BETWEEN 79 AND 89;  -- Age 79-89 at admission;