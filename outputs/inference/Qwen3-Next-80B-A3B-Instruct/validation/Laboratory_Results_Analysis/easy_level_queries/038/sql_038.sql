SELECT MIN(le.valuenum) AS min_hemoglobin
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON a.hadm_id = di.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
JOIN physionet-data.mimiciv_3_1_hosp.labevents le ON a.hadm_id = le.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dli ON le.itemid = dli.itemid
WHERE p.gender = 'M'
  AND p.anchor_age = 50
  AND LOWER(did.long_title) LIKE '%ischemic stroke%'
  AND LOWER(dli.label) IN ('hemoglobin', 'hgb', 'hb')
  AND le.charttime >= a.admittime
  AND le.charttime <= a.admittime + INTERVAL 24 HOUR
  AND le.valuenum IS NOT NULL;