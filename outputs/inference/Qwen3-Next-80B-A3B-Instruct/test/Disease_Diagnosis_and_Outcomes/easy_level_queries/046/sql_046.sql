SELECT STDDEV(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS sd_hospital_los_days
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 43 AND 53
  AND d.seq_num = 1
  AND (
    did.long_title LIKE '%hemorrhagic stroke%'
    OR did.long_title LIKE '%intracerebral hemorrhage%'
    OR did.long_title LIKE '%subarachnoid hemorrhage%'
    OR did.long_title LIKE '%intracranial hemorrhage%'
    OR did.long_title LIKE '%hemorrhagic cerebrovascular accident%'
  );