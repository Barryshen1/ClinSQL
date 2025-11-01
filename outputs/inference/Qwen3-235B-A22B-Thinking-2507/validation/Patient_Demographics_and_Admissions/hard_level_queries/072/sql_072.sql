WITH base_cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND a.admission_location = 'TRANSFER FROM SKILLED NURSING FACILITY'
    AND a.insurance = 'Medicare'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 10 AND d.icd_code IN ('J96.00', 'J96.01', 'J96.02', 'J96.03'))
      OR 
      (d.icd_version = 9 AND d.icd_code IN ('51881', '51882', '51884', '51885', '51886', '51887'))
    )
    AND (
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
    ) BETWEEN 77 AND 87
),
readmission_status AS (
  SELECT 
    bc.*,
    TIMESTAMP_DIFF(bc.dischtime, bc.admittime, HOUR) / 24.0 AS los_days,
    CASE WHEN bc.hospital_expire_flag = 0 THEN 1 ELSE 0 END AS discharged_alive,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = bc.subject_id
          AND a2.admittime > bc.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(bc.dischtime, INTERVAL 30 DAY)
          AND a2.hadm_id != bc.hadm_id
      ) THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM base_cohort bc
)
SELECT 
  COUNTIF(discharged_alive = 1 AND readmitted_30d = 1) * 1.0 / 
    NULLIF(COUNTIF(discharged_alive = 1), 0) AS readmission_rate,
  APPROX_QUANTILES(IF(discharged_alive = 1 AND readmitted_30d = 1, los_days, NULL), 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(IF(readmitted_30d = 0, los_days, NULL), 100)[OFFSET(50)] AS median_los_not_readmitted,
  COUNTIF(los_days > 8) * 100.0 / COUNT(*) AS percent_los_gt_8
FROM readmission_status;