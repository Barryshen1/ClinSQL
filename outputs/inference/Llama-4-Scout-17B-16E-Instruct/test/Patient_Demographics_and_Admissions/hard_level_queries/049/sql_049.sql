WITH 
-- Identify target population
target_population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    p.gender,
    a.admission_location,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.insurance
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 61 AND 71
    AND a.admission_location = 'SNF'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
      AND d.seq_num = 1  -- Principal diagnosis
      AND d.icd_code LIKE '584%'  -- AKI ICD code
    )
    AND a.insurance = 'Medicare'
),

-- Identify readmissions within 30 days
readmissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    target_population tp 
      ON a.subject_id = tp.subject_id AND a.hadm_id > tp.hadm_id
  WHERE 
    a.admittime <= TIMESTAMP_ADD(tp.dischtime, INTERVAL 30 DAY)
)

-- Calculate index LOS and categorize patients
SELECT 
  COUNT(DISTINCT CASE WHEN r.hadm_id IS NOT NULL THEN tp.hadm_id END) / COUNT(DISTINCT tp.hadm_id) * 100 AS thirty_day_readmission_rate,
  APPROX_QUANTILES(DATEDIFF(tp.dischtime, tp.admittime), 0.5) FILTER (WHERE r.hadm_id IS NOT NULL)[OFFSET(0)] AS median_los_readmitted,
  APPROX_QUANTILES(DATEDIFF(tp.dischtime, tp.admittime), 0.5) FILTER (WHERE r.hadm_id IS NULL)[OFFSET(0)] AS median_los_not_readmitted,
  COUNT(DISTINCT CASE WHEN DATEDIFF(tp.dischtime, tp.admittime) > 6 THEN tp.hadm_id END) / COUNT(DISTINCT tp.hadm_id) * 100 AS percent_stays_over_six_days
FROM 
  target_population tp
  LEFT JOIN readmissions r ON tp.hadm_id = r.hadm_id;