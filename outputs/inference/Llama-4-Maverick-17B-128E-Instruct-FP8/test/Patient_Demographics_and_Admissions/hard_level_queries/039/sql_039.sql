WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    p.anchor_age,
    a.insurance
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND a.insurance = 'Medicare'
),
diagnosis AS (
  SELECT 
    hadm_id,
    icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_version = 10  
    AND seq_num = 1  
    AND icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Acute respiratory failure%')
),
cohort_diagnosis AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.discharge_location
  FROM 
    cohort c
  INNER JOIN 
    diagnosis d ON c.hadm_id = d.hadm_id
),
readmissions AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime) AS prev_dischtime
  FROM 
    cohort_diagnosis
),
los_data AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los,
    CASE 
      WHEN DATETIME_DIFF(admittime, LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime), DAY) <= 30 THEN 1
      ELSE 0
    END AS readmitted
  FROM 
    readmissions
),
metrics AS (
  SELECT 
    AVG(CASE WHEN readmitted = 1 THEN 1 ELSE 0 END) AS readmission_rate,
    APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, DAY), 100)[OFFSET(50)] AS median_los,
    AVG(CASE WHEN DATETIME_DIFF(dischtime, admittime, DAY) > 9 THEN 1 ELSE 0 END) AS percent_los_gt_9
  FROM 
    los_data
),
readmitted_los AS (
  SELECT 
    readmitted,
    APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, DAY), 100)[OFFSET(50)] AS median_los_readmitted
  FROM 
    los_data
  GROUP BY 
    readmitted
)
SELECT 
  m.readmission_rate,
  rl1.median_los_readmitted AS median_los_readmitted,
  rl0.median_los_readmitted AS median_los_not_readmitted,
  m.percent_los_gt_9
FROM 
  metrics m
CROSS JOIN 
  (SELECT median_los_readmitted FROM readmitted_los WHERE readmitted = 1) rl1
CROSS JOIN 
  (SELECT median_los_readmitted FROM readmitted_los WHERE readmitted = 0) rl0;