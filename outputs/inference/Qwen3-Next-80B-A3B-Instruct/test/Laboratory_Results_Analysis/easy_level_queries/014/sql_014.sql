SELECT APPROX_QUANTILES(le.valuenum, 100)[OFFSET(75)] AS p75_hemoglobin_gdl
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON a.hadm_id = le.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
WHERE p.anchor_age = 45
  AND p.gender = 'F'
  AND LOWER(did.long_title) LIKE '%gastrointestinal hemorrhage%'
  AND LOWER(dli.label) LIKE '%hemoglobin%'
  AND DATE(le.charttime) = DATE(a.dischtime)
  AND le.valuenum IS NOT NULL;