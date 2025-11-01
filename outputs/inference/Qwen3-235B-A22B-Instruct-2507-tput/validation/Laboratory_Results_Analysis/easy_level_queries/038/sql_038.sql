SELECT MIN(l.valuenum) AS min_hemoglobin
FROM `physionet-data.mimiciv_3_1_hosp`.patients p
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_icd ON di.icd_code = d_icd.icd_code AND di.icd_version = d_icd.icd_version
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents l ON a.hadm_id = l.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems d_lab ON l.itemid = d_lab.itemid
WHERE p.gender = 'M'
  AND d_icd.icd_version = 10
  AND d_icd.icd_code LIKE 'I63%'
  AND LOWER(d_lab.label) LIKE '%hemoglobin%'
  AND l.charttime >= a.admittime
  AND l.charttime <= DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
  AND l.valuenum IS NOT NULL;