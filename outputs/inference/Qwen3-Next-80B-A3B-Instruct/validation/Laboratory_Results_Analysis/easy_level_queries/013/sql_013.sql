SELECT MAX(le.valuenum) AS max_peak_serum_creatinine_mg_dL
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  ON p.subject_id = di.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
  ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
JOIN physionet-data.mimiciv_3_1_hosp.labevents le
  ON p.subject_id = le.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dli
  ON le.itemid = dli.itemid
WHERE p.gender = 'F'
  AND did.long_title LIKE '%COPD%'
  AND dli.label = 'Creatinine'
  AND le.valueuom = 'mg/dL'
  AND le.valuenum IS NOT NULL;