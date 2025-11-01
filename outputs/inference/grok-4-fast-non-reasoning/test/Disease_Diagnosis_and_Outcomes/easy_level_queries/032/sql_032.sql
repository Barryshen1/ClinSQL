WITH aki_admissions AS (
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
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND d.seq_num = 1
    AND d.icd_version IN ('9', '10')
    AND (
      (d.icd_version = '10' AND d.icd_code LIKE 'N17%') OR
      (d.icd_version = '9' AND d.icd_code LIKE '584%')
    )
    AND a.hospital_expire_flag = 0
    AND a.dischtime > a.admittime  -- Ensure positive LOS
    AND EXTRACT(YEAR FROM a.admittime) >= 2008
)
SELECT 
  PERCENTILE_CONT(0.25, los_days) OVER() AS q1,
  PERCENTILE_CONT(0.75, los_days) OVER() AS q3,
  PERCENTILE_CONT(0.75, los_days) OVER() - PERCENTILE_CONT(0.25, los_days) OVER() AS iqr
FROM aki_admissions
WHERE los_days IS NOT NULL;