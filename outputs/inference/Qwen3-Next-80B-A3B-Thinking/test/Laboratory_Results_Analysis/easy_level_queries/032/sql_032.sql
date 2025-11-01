SELECT STDDEV_SAMP(labevents.valuenum) AS creatinine_stddev
FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS labevents
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d_labitems
  ON labevents.itemid = d_labitems.itemid
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
  ON labevents.hadm_id = admissions.hadm_id
  AND labevents.subject_id = admissions.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  ON admissions.subject_id = patients.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diagnoses_icd
  ON admissions.subject_id = diagnoses_icd.subject_id
  AND admissions.hadm_id = diagnoses_icd.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_icd_diagnoses
  ON diagnoses_icd.icd_code = d_icd_diagnoses.icd_code
  AND diagnoses_icd.icd_version = d_icd_diagnoses.icd_version
WHERE d_labitems.label = 'CREATININE'
  AND patients.gender = 'M'
  AND patients.anchor_age = 90
  AND (d_icd_diagnoses.long_title LIKE '%COPD%' OR d_icd_diagnoses.long_title LIKE '%chronic obstructive pulmonary disease%')
  AND labevents.charttime >= admissions.admittime
  AND labevents.charttime <= admissions.admittime + INTERVAL 24 HOUR;