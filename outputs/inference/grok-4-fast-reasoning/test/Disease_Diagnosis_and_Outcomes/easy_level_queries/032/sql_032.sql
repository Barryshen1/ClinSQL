WITH cohort AS (
  SELECT 
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON 
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '584%') 
      OR 
      (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
    )
)
SELECT 
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] - APPROX_QUANTILES(los, 4)[OFFSET(1)] AS iqr
FROM cohort;