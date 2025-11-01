SELECT MIN(le.valuenum) AS min_serum_sodium
FROM physionet-data.mimiciv_3_1_hosp.labevents le
JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON le.hadm_id = a.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON le.hadm_id = di.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
JOIN physionet-data.mimiciv_3_1_hosp.patients p ON le.subject_id = p.subject_id
WHERE LOWER(dl.label) LIKE '%sodium%'
  AND LOWER(did.long_title) LIKE '%heart failure%'
  AND p.gender = 'M'
  AND p.anchor_age = 65
  AND le.valuenum IS NOT NULL;