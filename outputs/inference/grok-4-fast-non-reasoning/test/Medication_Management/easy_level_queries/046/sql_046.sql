WITH eligible_prescriptions AS (
  SELECT 
    pres.subject_id,
    pres.hadm_id,
    pres.starttime,
    pres.stoptime,
    DATE_DIFF(DATE(pres.stoptime), DATE(pres.starttime), DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON pat.subject_id = pres.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pres.hadm_id = adm.hadm_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 90 AND 100
    AND adm.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND (LOWER(pres.drug) LIKE '%spironolactone%' OR LOWER(pres.drug) LIKE '%eplerenone%')
    AND pres.stoptime IS NOT NULL
    AND pres.starttime IS NOT NULL
    AND DATE(pres.stoptime) > DATE(pres.starttime)
),
patient_medians AS (
  SELECT 
    subject_id,
    PERCENTILE_CONT(duration_days, 0.5) OVER (PARTITION BY subject_id) AS patient_median_duration
  FROM 
    eligible_prescriptions
)
SELECT 
  APPROX_QUANTILES(patient_median_duration, 2)[OFFSET(1)] AS median_duration_days
FROM 
  patient_medians
  CROSS JOIN (SELECT 1 AS dummy) -- Ensures single row output
WHERE 
  patient_median_duration IS NOT NULL;