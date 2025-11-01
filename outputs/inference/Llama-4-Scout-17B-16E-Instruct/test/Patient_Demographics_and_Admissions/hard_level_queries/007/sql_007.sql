WITH 
-- Identify target population
target_population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    a.admission_type,
    a.admission_location,
    a.dischtime,
    a.hospital_expire_flag,
    d_icd.long_title AS diagnosis,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS index_los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
      ON di.icd_code = d_icd.icd_code AND di.icd_version = d_icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.admission_type = 'Emergency'
    AND d_icd.long_title LIKE '%Transient ischemic attack%'
    AND a.insurance = 'Medicare'
),

-- Identify readmissions within 30 days
readmissions AS (
  SELECT 
    hadm_id,
    dischtime,
    LEAD(dischtime) OVER (PARTITION BY subject_id ORDER BY dischtime) AS next_dischtime,
    index_los
  FROM 
    target_population
),

-- Flag for readmission within 30 days
readmitted AS (
  SELECT 
    hadm_id,
    dischtime,
    next_dischtime,
    index_los,
    CASE 
      WHEN next_dischtime IS NOT NULL AND next_dischtime <= TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS readmitted
  FROM 
    readmissions
)

-- Calculate desired metrics
SELECT 
  COUNT(DISTINCT CASE WHEN readmitted = 1 THEN hadm_id END) / COUNT(DISTINCT hadm_id) AS thirty_day_readmission_rate,
  APPROX_QUANTILES(CASE WHEN readmitted = 1 THEN index_los END, 1000)[500] AS median_index_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted = 0 THEN index_los END, 1000)[500] AS median_index_los_not_readmitted,
  COUNT(DISTINCT CASE WHEN index_los > 10 THEN hadm_id END) / COUNT(DISTINCT hadm_id) * 100 AS percent_index_stays_over_10_days
FROM 
  readmitted;