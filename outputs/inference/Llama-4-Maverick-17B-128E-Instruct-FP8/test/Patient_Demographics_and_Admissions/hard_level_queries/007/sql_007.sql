WITH 
eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 83 AND 93
),
index_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, 
         ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients ep ON a.subject_id = ep.subject_id
  WHERE a.insurance = 'Medicare'
    AND a.admission_type = 'EMERGENCY'
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_version = 10 
        AND icd_code IN ('G45.9', 'G45.8')  
      )
),
admission_outcomes AS (
  SELECT ia.hadm_id, ia.admittime, ia.dischtime, 
         DATETIME_DIFF(ia.dischtime, ia.admittime, DAY) AS los,
         CASE 
           WHEN EXISTS (
             SELECT 1 
             FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
             WHERE a2.subject_id = ia.subject_id 
               AND a2.admittime > ia.dischtime 
               AND DATETIME_DIFF(a2.admittime, ia.dischtime, DAY) <= 30
           ) THEN 1 ELSE 0 END AS readmitted
  FROM index_admissions ia
  WHERE ia.admission_rank = 1  
),
los_data AS (
  SELECT 
    COUNT(*) AS total_admissions,
    SUM(readmitted) AS total_readmitted,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(CASE WHEN readmitted = 1 THEN los END, 100)[OFFSET(50)] AS median_los_readmitted,
    APPROX_QUANTILES(CASE WHEN readmitted = 0 THEN los END, 100)[OFFSET(50)] AS median_los_not_readmitted,
    SUM(CASE WHEN los > 10 THEN 1 ELSE 0 END) AS count_los_gt_10
  FROM admission_outcomes
)
SELECT 
  total_readmitted / total_admissions AS readmission_rate,
  median_los_readmitted,
  median_los_not_readmitted,
  (count_los_gt_10 / total_admissions) * 100 AS percent_los_gt_10
FROM los_data;