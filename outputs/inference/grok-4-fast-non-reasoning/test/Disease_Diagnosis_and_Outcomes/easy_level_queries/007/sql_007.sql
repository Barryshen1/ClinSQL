WITH primary_ugib AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age >= 84
    AND p.anchor_age <= 94
    AND a.hospital_expire_flag = 0
    AND d.seq_num = 1
    AND (
      d.icd_code = 'K92.2' OR
      d.icd_code LIKE 'K25.0%' OR d.icd_code LIKE 'K25.4%' OR d.icd_code LIKE 'K25.6%' OR
      d.icd_code LIKE 'K26.0%' OR d.icd_code LIKE 'K26.4%' OR d.icd_code LIKE 'K26.6%' OR
      d.icd_code = 'K22.11'
    )
    AND a.hadm_id IS NOT NULL
    AND a.dischtime > a.admittime
    AND EXTRACT(YEAR FROM a.admittime) >= 2008
)
SELECT 
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] - APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS iqr
FROM 
  primary_ugib
WHERE 
  los_days > 0;