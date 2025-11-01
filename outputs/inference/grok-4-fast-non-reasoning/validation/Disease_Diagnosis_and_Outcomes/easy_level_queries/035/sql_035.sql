WITH qualifying_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON 
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND DATE_DIFF(a.admittime, DATE(p.anchor_year, 1, 1), YEAR) = 70
    AND EXTRACT(YEAR FROM a.admittime) >= p.anchor_year
    AND d.seq_num = 1
    AND d.icd_code LIKE 'K92.2%'
    AND d.icd_version = '10'  -- Focus on ICD-10 for upper GI bleed
    AND a.hospital_expire_flag = 0
    AND a.dischtime > a.admittime  -- Ensure positive LOS
)
SELECT 
  PERCENTILE_CONT(0.75) OVER() AS p75_los_days
FROM 
  qualifying_admissions;