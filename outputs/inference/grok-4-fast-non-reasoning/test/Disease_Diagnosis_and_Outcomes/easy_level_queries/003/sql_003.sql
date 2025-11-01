WITH eligible_admissions AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
    AND EXTRACT(YEAR FROM a.admittime) >= p.anchor_year
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND (
      (CAST(d.icd_version AS STRING) = '10' AND (STARTS_WITH(icd.icd_code, 'I20') OR STARTS_WITH(icd.icd_code, 'I21') OR STARTS_WITH(icd.icd_code, 'I22')))
      OR
      (CAST(d.icd_version AS STRING) = '9' AND (icd.icd_code LIKE '410%' OR icd.icd_code LIKE '411%' OR icd.icd_code LIKE '414%'))
    )
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.hospital_expire_flag = 0
    AND a.dischtime > a.admittime  -- Ensure positive LOS
)
SELECT 
  PERCENTILE_CONT(los, 0.25) AS p25_los_days
FROM eligible_admissions;