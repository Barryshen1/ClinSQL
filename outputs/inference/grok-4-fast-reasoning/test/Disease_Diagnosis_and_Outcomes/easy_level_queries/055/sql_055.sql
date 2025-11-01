WITH cohort AS (
  SELECT 
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND d.seq_num = 1
    AND (
      (d.icd_version = '9' AND d.icd_code LIKE '584%')
      OR
      (d.icd_version = '10' AND d.icd_code LIKE 'N17%')
    )
    AND a.dischtime > a.admittime
)
SELECT 
  PERCENTILE_CONT(los_days, 0.75) AS p75_hospital_los_days
FROM cohort;