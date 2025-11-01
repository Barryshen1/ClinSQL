SELECT APPROX_QUANTILES(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY), 4)[OFFSET(3)] AS p75_hospital_los_days
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
  ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 37 AND 47
  AND d.seq_num = 1
  AND (LOWER(dicd.long_title) LIKE '%acute kidney injury%'
       OR LOWER(dicd.long_title) LIKE '%acute renal failure%');