SELECT DISTINCT PERCENTILE_CONT(lab.valuenum, 0.75) OVER() AS p75_serum_glucose_mgdl
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
  ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
JOIN physionet-data.mimiciv_3_1_hosp.labevents lab
  ON a.subject_id = lab.subject_id AND a.hadm_id = lab.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dlab
  ON lab.itemid = dlab.itemid
WHERE p.gender = 'F'
  AND p.anchor_age = 82
  AND LOWER(did.long_title) LIKE '%ischemic stroke%'
  AND LOWER(dlab.label) LIKE '%glucose%'
  AND lab.valueuom = 'mg/dL'
  AND lab.valuenum IS NOT NULL
  AND lab.charttime >= a.admittime
  AND lab.charttime <= a.dischtime;