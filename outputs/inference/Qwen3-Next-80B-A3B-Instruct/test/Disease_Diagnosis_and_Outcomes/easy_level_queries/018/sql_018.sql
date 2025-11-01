SELECT STDDEV(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS sd_hospital_los
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
  ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 45 AND 55
  AND (
    dicd.long_title LIKE '%hemorrhagic stroke%'
    OR dicd.long_title LIKE '%intracerebral hemorrhage%'
    OR dicd.long_title LIKE '%subarachnoid hemorrhage%'
    OR dicd.long_title LIKE '%intracranial hemorrhage%'
    OR d.icd_code IN ('430', '431', '432')  -- ICD-9
    OR d.icd_code IN ('I60', 'I61', 'I62')  -- ICD-10
  );