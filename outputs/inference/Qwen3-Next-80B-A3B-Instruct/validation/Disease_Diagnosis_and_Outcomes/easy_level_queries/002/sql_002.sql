SELECT APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75_hospital_los_days
FROM (
  SELECT TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND d.seq_num = 1
    AND (LOWER(dicd.long_title) LIKE '%acute kidney injury%'
         OR LOWER(dicd.long_title) LIKE '%acute renal failure%')
) AS filtered_los;