WITH patient_prescriptions AS (
  SELECT 
    pr.pharmacy_id,
    pr.duration AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.subject_id = pr.subject_id 
    AND a.hadm_id = pr.hadm_id
  WHERE 
    p.gender = 'M'
    AND DATE_DIFF(a.admittime, DATE(p.dob), DAY) / 365.25 BETWEEN 62 AND 72  -- Age at admission
    AND LOWER(pr.drug) LIKE '%amiodarone%'
    AND (LOWER(pr.route) LIKE '%oral%' OR LOWER(pr.route) LIKE '%po%')  -- Oral routes only
    AND pr.duration IS NOT NULL 
    AND pr.duration > 0
    AND a.hospital_expire_flag = 0
  GROUP BY 
    pr.pharmacy_id, pr.duration  -- Unique prescription durations
)
SELECT 
  PERCENTILE_CONT(duration_days, 0.25) AS q1_days,
  PERCENTILE_CONT(duration_days, 0.75) AS q3_days,
  (PERCENTILE_CONT(duration_days, 0.75) - PERCENTILE_CONT(duration_days, 0.25)) AS iqr_days
FROM 
  patient_prescriptions;