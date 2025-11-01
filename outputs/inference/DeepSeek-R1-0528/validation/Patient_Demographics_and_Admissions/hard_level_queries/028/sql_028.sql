WITH index_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN a.dischtime > DATETIME_ADD(a.admittime, INTERVAL 7 DAY) THEN 1 
      ELSE 0 
    END AS los_over_7
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '682%') 
      OR 
      (d.icd_version = 10 AND d.icd_code LIKE 'L03%')
    )
    AND a.hospital_expire_flag = 0
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 55 AND 65
),
readmission_flag_data AS (
  SELECT 
    *,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2 
        WHERE a2.subject_id = i.subject_id
          AND a2.admittime > i.dischtime
          AND a2.admittime <= DATETIME_ADD(i.dischtime, INTERVAL 30 DAY)
          AND a2.hadm_id != i.hadm_id
      ) THEN 1 
      ELSE 0 
    END AS had_readmission
  FROM index_admissions i
)
SELECT
  ROUND(100.0 * SUM(had_readmission) / COUNT(*), 2) AS readmission_rate_percent,
  (SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(50)] 
   FROM readmission_flag_data 
   WHERE had_readmission = 1) AS median_los_readmitted,
  (SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(50)] 
   FROM readmission_flag_data 
   WHERE had_readmission = 0) AS median_los_non_readmitted,
  ROUND(100.0 * AVG(los_over_7), 2) AS percent_los_over_7
FROM readmission_flag_data;