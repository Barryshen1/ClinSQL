SELECT MIN(le.valuenum) AS min_troponin_value
FROM `physionet-data.mimiciv_3_1_hosp`.patients p
JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_icd ON di.icd_code = d_icd.icd_code AND di.icd_version = d_icd.icd_version
JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le ON a.hadm_id = le.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems d_lab ON le.itemid = d_lab.itemid
WHERE p.gender = 'M'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) = 57
  AND (
    d_icd.icd_code LIKE 'I21%' 
    OR d_icd.icd_code LIKE 'I22%' 
    OR d_icd.icd_code = 'I200'
  )
  AND LOWER(d_lab.label) LIKE '%tropinin%'
  AND le.valuenum IS NOT NULL
  AND le.valuenum >= 0  -- Troponin can't be negative;