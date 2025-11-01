WITH patient_admissions AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year, 
    a.hadm_id, 
    a.admittime,
    -- Calculate exact age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'  -- Only male patients
),
arb_prescriptions AS (
  SELECT 
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    -- Calculate duration in fractional days (handles <1 day)
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) / (24 * 60 * 60.0) AS duration_days
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pa.subject_id = pr.subject_id 
    AND pa.hadm_id = pr.hadm_id
  WHERE 
    pa.age_at_admission BETWEEN 38 AND 48  -- Age filter
    AND pr.stoptime >= pr.starttime  -- Exclude invalid durations
    AND REGEXP_CONTAINS(  -- Match ARB drug names
      LOWER(pr.drug), 
      r'losartan|valsartan|irbesartan|candesartan|telmisartan|olmesartan|azilsartan'
    )
),
quantiles AS (
  SELECT 
    APPROX_QUANTILES(duration_days, 100) AS arr
  FROM arb_prescriptions
)
-- Compute 75th percentile duration safely
SELECT 
  IF(arr IS NOT NULL, arr[OFFSET(75)], NULL) AS percentile_75_duration_days
FROM quantiles;