WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - 2008)) AS age_at_admission,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS hospital_los
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
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - 2008)) BETWEEN 71 AND 81
    AND d.seq_num = 1
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
      OR
      (d.icd_version = 9 AND (d.icd_code LIKE '4331%' OR d.icd_code LIKE '4341%' OR d.icd_code = '436'))
    )
    AND a.dischtime > a.admittime  -- Exclude invalid LOS <=0
)

SELECT 
  APPROX_QUANTILES(hospital_los, 4)[OFFSET(3)] - APPROX_QUANTILES(hospital_los, 4)[OFFSET(1)] AS iqr_hospital_los
FROM 
  cohort;