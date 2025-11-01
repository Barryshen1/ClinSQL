SELECT APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS p75_hospital_los_days
FROM (
  SELECT 
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND (
      LOWER(dicd.long_title) LIKE '%hemorrhagic stroke%'
      OR LOWER(dicd.long_title) LIKE '%intracerebral hemorrhage%'
      OR LOWER(dicd.long_title) LIKE '%subarachnoid hemorrhage%'
      OR LOWER(dicd.long_title) LIKE '%intracranial hemorrhage%'
      OR LOWER(dicd.long_title) LIKE '%cerebral hemorrhage%'
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
) AS filtered_los;