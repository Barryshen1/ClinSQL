WITH patient_dob AS (
  SELECT 
    subject_id,
    gender,
    DATE(anchor_year - anchor_age, 1, 1) AS dob
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients`
),
eligible_prescriptions AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.dose_val_rx,
    p.dose_unit_rx,
    p.starttime,
    p.stoptime,
    DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN 
    patient_dob pat ON p.subject_id = pat.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.hadm_id = a.hadm_id
  WHERE 
    pat.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - EXTRACT(YEAR FROM pat.dob) 
        - (CASE WHEN (DATE(a.admittime) < DATE(EXTRACT(YEAR FROM a.admittime), MONTH(pat.dob), DAY(pat.dob))) THEN 1 ELSE 0 END) 
        BETWEEN 75 AND 85
    AND LOWER(p.drug) LIKE '%atorvastatin%'
    AND p.dose_val_rx BETWEEN 40 AND 80
    AND p.dose_unit_rx = 'MG'
    AND p.stoptime IS NOT NULL
    AND p.starttime < p.stoptime
    AND DATE_DIFF(p.stoptime, p.starttime, DAY) > 0
)

SELECT 
  PERCENTILE_CONT(duration_days, 0.25) OVER() AS q1_duration_days,
  PERCENTILE_CONT(duration_days, 0.75) OVER() AS q3_duration_days,
  (PERCENTILE_CONT(duration_days, 0.75) OVER() - PERCENTILE_CONT(duration_days, 0.25) OVER()) AS iqr_duration_days,
  COUNT(*) AS num_qualifying_prescriptions,
  AVG(duration_days) AS mean_duration_days
FROM 
  eligible_prescriptions;