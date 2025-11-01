WITH qualifying_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
    AND EXTRACT(YEAR FROM a.admittime) >= p.anchor_year
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND d.seq_num = 1
    AND (
      d.icd_code IN ('E10.10', 'E10.11', 'E13.10', 'E13.11', 'E11.00', 'E11.01', 'E11.10', 'E11.11')
      OR icd.long_title LIKE '%ketoacidosis%' 
      OR icd.long_title LIKE '%hyperosmolar%'
    )
    AND a.hospital_expire_flag = 0
    AND a.dischtime > a.admittime  -- Ensure valid LOS
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
)
SELECT 
  APPROX_QUANTILES(los_days, 4) OVER() [OFFSET(0)] AS p25_los_days
FROM 
  qualifying_admissions
WHERE 
  los_days IS NOT NULL;