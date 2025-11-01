SELECT APPROX_QUANTILES(i.los, 100)[OFFSET(25)] AS p25_los
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
JOIN physionet-data.mimiciv_3_1_icu.icustays i ON a.hadm_id = i.hadm_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 74 AND 84
  AND d.seq_num = 1
  AND (
    dd.long_title LIKE '%upper gastrointestinal hemorrhage%'
    OR dd.long_title LIKE '%gastrointestinal hemorrhage%'
    OR dd.long_title LIKE '%gastric hemorrhage%'
    OR dd.long_title LIKE '%esophageal hemorrhage%'
    OR dd.long_title LIKE '%duodenal hemorrhage%'
    OR dd.long_title LIKE '%peptic ulcer hemorrhage%'
    OR dd.long_title LIKE '%hematemesis%'
    OR dd.long_title LIKE '%melena%'
  )
  AND dd.long_title NOT LIKE '%lower%';