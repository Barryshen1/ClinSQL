WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admission_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
),
nitrate_prescriptions AS (
  SELECT 
    ep.subject_id,
    ep.hadm_id,
    pr.starttime,
    pr.stoptime
  FROM 
    eligible_patients ep
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON 
    ep.hadm_id = pr.hadm_id
  WHERE 
    (LOWER(pr.drug) LIKE '%nitrogly%' 
     OR LOWER(pr.drug) LIKE '%isosorbide%' 
     OR LOWER(pr.drug) LIKE '%nitrate%')
    AND pr.drug_type = 'main'
    AND pr.route IN ('IV', 'PO', 'SL', 'SUBLINGUAL')
    AND pr.stoptime > pr.starttime
),
nitrate_durations AS (
  SELECT 
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    DATE_DIFF(DATE(stoptime), DATE(starttime), DAY) AS duration_days
  FROM 
    nitrate_prescriptions
  WHERE 
    DATE_DIFF(DATE(stoptime), DATE(starttime), DAY) > 0
)
SELECT 
  MAX(duration_days) AS max_single_prescription_duration_days
FROM 
  nitrate_durations;