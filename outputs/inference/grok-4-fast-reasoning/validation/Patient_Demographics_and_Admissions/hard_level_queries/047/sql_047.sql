WITH index_adms AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.hospital_expire_flag = 0
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 
       AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%'))
      OR
      (d.icd_version = 10 
       AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
    )
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 68 AND 78
),
readmitted AS (
  SELECT 
    ia.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.hadm_id != ia.hadm_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) AS is_readmitted
  FROM index_adms ia
)
SELECT 
  ROUND(AVG(CAST(is_readmitted AS FLOAT)) * 100, 2) AS readmission_rate_pct,
  ROUND((SELECT PERCENTILE_CONT(los_days, 0.5) FROM readmitted r2 WHERE r2.is_readmitted), 2) AS median_los_readmitted_days,
  ROUND((SELECT PERCENTILE_CONT(los_days, 0.5) FROM readmitted r2 WHERE NOT r2.is_readmitted), 2) AS median_los_nonreadmitted_days,
  ROUND(AVG(CAST(los_days > 4 AS FLOAT)) * 100, 2) AS pct_los_gt4_days
FROM readmitted;