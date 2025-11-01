WITH 
-- Identify index admissions
index_admissions AS (
  SELECT 
    a1.subject_id,
    a1.hadm_id,
    a1.admittime,
    a1.dischtime,
    a1.admission_type,
    a1.admission_location,
    p.anchor_age,
    p.gender,
    p.dod,
    a1.hospital_expire_flag,
    DATE_DIFF(a1.dischtime, a1.admittime) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a1
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a1.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a1.insurance = 'Medicare'
    AND a1.admission_type = 'Emergency'
    AND a1.admission_location = 'ED'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a1.hadm_id
      AND d.seq_num = 1
      AND (d.icd_code LIKE '595.9' OR d.icd_code LIKE 'N30.0%')
    )
),

-- Identify readmissions
readmissions AS (
  SELECT 
    subject_id,
    hadm_id,
    dischtime,
    LEAD(dischtime) OVER (PARTITION BY subject_id ORDER BY dischtime) AS next_admittime
  FROM 
    index_admissions
),

-- Flag readmitted patients
readmitted_patients AS (
  SELECT 
    subject_id,
    hadm_id,
    los_days,
    CASE 
      WHEN next_admittime IS NOT NULL AND next_admittime - dischtime <= INTERVAL 30 DAY THEN 1 
      ELSE 0 
    END AS readmitted
  FROM 
    readmissions
)

-- Calculate statistics
SELECT 
  AVG(readmitted) AS readmission_rate,
  APPROX_QUANTILES(los_days, 0.5)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted = 0 THEN los_days END, 0.5)[OFFSET(1)] AS median_los_not_readmitted,
  AVG(CAST(los_days > 9 AS INT64)) AS percent_los_gt_9_overall,
  AVG(CAST(CASE WHEN readmitted = 1 THEN los_days > 9 ELSE FALSE END AS INT64)) AS percent_los_gt_9_readmitted,
  AVG(CAST(CASE WHEN readmitted = 0 THEN los_days > 9 ELSE FALSE END AS INT64)) AS percent_los_gt_9_not_readmitted
FROM 
  readmitted_patients;