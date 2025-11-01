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
    d.icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_location LIKE '%SNF%'
    AND d.seq_num = 1  -- Principal diagnosis
    AND d.icd_code LIKE '% urinary tract infection%'
),

-- Identify readmissions within 30 days
readmissions AS (
  SELECT 
    hadm_id,
    subject_id,
    dischtime,
    LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY dischtime) AS readmit_time
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Calculate LOS and identify readmitted patients
patient_stays AS (
  SELECT 
    tp.hadm_id,
    tp.subject_id,
    tp.admittime,
    tp.dischtime,
    TIMESTAMP_DIFF(tp.dischtime, tp.admittime, DAY) AS los,
    CASE 
      WHEN r.readmit_time IS NOT NULL AND r.readmit_time <= TIMESTAMP_ADD(tp.dischtime, INTERVAL 30 DAY) THEN 1 
      ELSE 0 
    END AS readmitted
  FROM 
    target_population tp
  LEFT JOIN 
    readmissions r ON tp.hadm_id = r.hadm_id
)

-- Final calculations
SELECT 
  COUNT(DISTINCT CASE WHEN readmitted = 1 THEN hadm_id END) / COUNT(DISTINCT hadm_id) AS readmission_rate,
  APPROX_QUANTILES(CASE WHEN readmitted = 1 THEN los END, 1000)[500] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted = 0 THEN los END, 1000)[500] AS median_los_not_readmitted,
  SUM(CASE WHEN los > 6 THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id) * 100 AS percent_stays_over_6_days
FROM 
  patient_stays;