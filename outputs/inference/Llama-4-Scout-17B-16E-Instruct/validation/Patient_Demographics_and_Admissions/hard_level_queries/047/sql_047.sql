WITH 
-- Define target population
target_population AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    p.gender,
    p.anchor_age,
    di.icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON 
    a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_location = 'ED'
    AND di.seq_num = 1  -- Principal diagnosis
    AND di.icd_code LIKE '430%'  -- Hemorrhagic stroke
    AND a.insurance = 'Medicare'
),

-- Identify readmissions within 30 days
readmissions AS (
  SELECT 
    hadm_id,
    dischtime,
    LEAST(TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY), CURRENT_TIMESTAMP) AS readm_endtime
  FROM 
    target_population
),

readmitted_patients AS (
  SELECT 
    rp.hadm_id AS index_hadm_id,
    ra.hadm_id AS readm_hadm_id
  FROM 
    readmissions rp
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` ra
  ON 
    rp.hadm_id = ra.prev_hadm_id
    AND ra.admittime BETWEEN TIMESTAMP_ADD(rp.dischtime, INTERVAL 1 DAY) AND rp.readm_endtime
)

-- Calculate required metrics
SELECT 
  COUNT(DISTINCT CASE WHEN readm_hadm_id IS NOT NULL THEN index_hadm_id END) / COUNT(DISTINCT index_hadm_id) AS readm_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DATE_DIFF(dischtime, admittime, DAY) FILTER (WHERE readm_hadm_id IS NULL)) AS median_los_non_readmitted,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DATE_DIFF(dischtime, admittime, DAY) FILTER (WHERE readm_hadm_id IS NOT NULL)) AS median_los_readmitted,
  AVG(DATE_DIFF(dischtime, admittime, DAY) > 4) AS pct_los_gt_4_days
FROM 
  target_population tp
  LEFT JOIN readmitted_patients rp
  ON tp.hadm_id = rp.index_hadm_id;