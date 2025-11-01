SELECT MIN(le.valuenum) AS min_serum_troponin
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON a.hadm_id = di.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
JOIN physionet-data.mimiciv_3_1_hosp.labevents le ON a.hadm_id = le.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dli ON le.itemid = dli.itemid
WHERE p.gender = 'M'
  AND (
    LOWER(did.long_title) LIKE '%acute coronary syndrome%'
    OR LOWER(did.long_title) LIKE '%myocardial infarction%'
    OR LOWER(did.long_title) LIKE '%unstable angina%'
    OR did.icd_code IN ('I21', 'I22', 'I24.8', 'I24.9')
  )
  AND LOWER(dli.label) LIKE '%troponin%'
  AND le.charttime >= a.admittime
  AND le.charttime <= a.dischtime
  AND le.valuenum IS NOT NULL;