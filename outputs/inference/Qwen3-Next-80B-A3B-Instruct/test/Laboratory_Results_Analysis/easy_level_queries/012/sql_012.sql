SELECT PERCENTILE_DISC(le.valuenum, 0.75) AS p75_platelet_count
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
JOIN physionet-data.mimiciv_3_1_hosp.labevents le ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dli ON le.itemid = dli.itemid
WHERE p.anchor_age = 87
  AND p.gender = 'F'
  AND di.icd_version = 10
  AND LOWER(did.long_title) LIKE '%hemorrhagic stroke%'
  AND DATE(le.charttime) = DATE(a.dischtime)
  AND LOWER(dli.label) LIKE '%platelet%'
  AND le.valuenum IS NOT NULL;