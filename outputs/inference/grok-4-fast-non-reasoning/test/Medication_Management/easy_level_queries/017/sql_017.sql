WITH patient_prescriptions AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admission_type,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
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
    AND p.anchor_age = 48  -- Specific 48-year-old male
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')  -- Inpatient admissions
    AND pr.drug = 'Warfarin'
    AND pr.starttime IS NOT NULL 
    AND pr.stoptime IS NOT NULL 
    AND pr.stoptime > pr.starttime  -- Valid duration
)
SELECT 
  AVG(duration_days) AS avg_warfarin_duration_days
FROM patient_prescriptions;