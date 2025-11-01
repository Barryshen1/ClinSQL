SELECT COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id
  AND adm.subject_id = diag.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd
  ON diag.icd_code = icd.icd_code
  AND diag.icd_version = icd.icd_version
WHERE
  pat.gender = 'M'
  AND adm.admission_location = 'EMERGENCY ROOM'
  AND adm.insurance = 'Medicare'
  AND diag.seq_num = 1  -- Principal diagnosis
  AND icd.long_title LIKE '%pneumonia%'  -- Pneumonia diagnosis
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) 
      BETWEEN 77 AND 87  -- Age 77-87 at admission
);