WITH index_cohort AS (
  -- Base cohort: male, Medicare, age 51-61, ED admission, principal acute pancreatitis, discharged alive
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id AS index_hadm_id,
    a.admittime AS index_admittime,
    a.dischtime AS index_dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS index_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id 
    AND CAST(a.hadm_id AS STRING) = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND EXTRACT(YEAR FROM a.admittime) = p.anchor_year
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.hospital_expire_flag = 0
    AND d.seq_num = 1
    AND (
      (d.icd_version = '10' AND d.icd_code LIKE 'K85%') OR
      (d.icd_version = '9' AND d.icd_code = '5770')
    )
),

cohort AS (
  SELECT 
    ic.*,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` ra
        WHERE ra.subject_id = ic.subject_id
          AND CAST(ra.hadm_id AS STRING) > CAST(ic.index_hadm_id AS STRING)  -- Subsequent admission (string comparison safe for IDs)
          AND ra.hospital_expire_flag = 0     -- Discharged alive
          AND DATE_DIFF(ra.admittime, ic.index_dischtime, DAY) <= 30
          AND ra.admittime > ic.index_dischtime  -- After index discharge
      ) THEN 1 
      ELSE 0 
    END AS readmitted
  FROM index_cohort ic
),

median_los AS (
  SELECT 
    readmitted,
    PERCENTILE_CONT(index_los, 0.5) AS median_index_los
  FROM cohort
  GROUP BY readmitted
),

overall_stats AS (
  SELECT 
    (SUM(CASE WHEN readmitted = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS readmission_rate_percent,
    (SUM(CASE WHEN index_los > 9 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percent_stays_gt_9_days,
    COUNT(*) AS total_index_stays
  FROM cohort
)

SELECT 
  o.readmission_rate_percent,
  o.percent_stays_gt_9_days,
  m0.median_index_los AS median_los_non_readmitted,
  m1.median_index_los AS median_los_readmitted,
  o.total_index_stays
FROM overall_stats o
CROSS JOIN median_los m0
CROSS JOIN median_los m1
WHERE m0.readmitted = 0 AND m1.readmitted = 1;