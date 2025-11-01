SELECT MIN(le.valuenum) AS min_admission_sodium
FROM `physionet-data.mimiciv_3_1_hosp`.patients p
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON p.subject_id = a.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON a.hadm_id = di.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_icd
  ON di.icd_code = d_icd.icd_code AND di.icd_version = d_icd.icd_version
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le
  ON a.hadm_id = le.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems d_lab
  ON le.itemid = d_lab.itemid
WHERE p.gender = 'M'
  AND p.anchor_age = 65
  AND LOWER(d_icd.long_title) LIKE '%heart failure%'
  AND LOWER(d_lab.label) = 'sodium'
  AND le.charttime >= a.admittime
  AND le.charttime <= DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
  AND le.valuenum IS NOT NULL;