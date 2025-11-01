WITH 
-- Target patient population
target_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender, COUNT(di.icd_code) AS num_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 63 AND 73
  AND di.icd_code LIKE '%785.52%'  -- Septic shock ICD-9 code, adjust as necessary
  GROUP BY p.subject_id, p.anchor_age, p.gender
  HAVING COUNT(di.icd_code) > 15
),

-- General inpatient population
general_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender, COUNT(di.icd_code) AS num_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  GROUP BY p.subject_id, p.anchor_age, p.gender
),

-- Calculate 90-day mortality and risk score for target patients
mortality_risk AS (
  SELECT tp.subject_id, 
         CASE 
           WHEN p.dod IS NOT NULL AND p.dod <= TIMESTAMP_ADD(a.admittime, INTERVAL 90 DAY) THEN 1
           ELSE 0
         END AS ninety_day_mortality,
         -- Simplified risk score calculation, adjust as necessary
         COALESCE(dc.drg_severity, 0) AS risk_score
  FROM target_patients tp
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON tp.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON tp.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` dc ON a.hadm_id = dc.hadm_id
),

-- Length of stay for survivors
los AS (
  SELECT tp.subject_id, 
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM target_patients tp
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON tp.subject_id = a.subject_id
  WHERE a.dischtime IS NOT NULL
),

-- Percentile calculation for target patient profile
percentile_los AS (
  SELECT 
    APPROX_QUANTILES(DATE_DIFF(a.dischtime, a.admittime, DAY), 100) WITHIN GROUP (ORDER BY DATE_DIFF(a.dischtime, a.admittime, DAY)) AS percentile_los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age = 68 AND a.dischtime IS NOT NULL
)

-- Final calculations
SELECT 
  AVG(mr.risk_score) AS mean_risk_score,
  AVG(mr.ninety_day_mortality) AS ninety_day_mortality_rate,
  AVG(l.los) AS survivor_los,
  (SELECT percentile_los[51] FROM percentile_los) AS percentile_los_50  -- Directly get the 50th percentile value
FROM mortality_risk mr
JOIN los l ON mr.subject_id = l.subject_id
CROSS JOIN percentile_los;