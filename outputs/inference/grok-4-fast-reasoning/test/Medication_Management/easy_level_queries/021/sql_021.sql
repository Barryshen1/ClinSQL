WITH cohort AS (
  SELECT 
    pr.subject_id,
    pr.hadm_id,
    pr.drug,
    pr.dose_val_rx,
    pr.dose_unit_rx,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
  WHERE 
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 75 AND 85
    AND pr.hadm_id IS NOT NULL
    AND LOWER(pr.drug) LIKE '%atorvastatin%'
    AND pr.dose_val_rx IS NOT NULL
    AND pr.dose_unit_rx IS NOT NULL
    AND UPPER(pr.dose_unit_rx) = 'MG'
    AND SAFE_CAST(pr.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) > 0
)
SELECT 
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr_duration_days
FROM cohort;