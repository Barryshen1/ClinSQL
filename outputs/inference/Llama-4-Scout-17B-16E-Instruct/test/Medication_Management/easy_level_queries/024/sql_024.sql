WITH patient_demographics AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 84 AND 94
),
prescription_durations AS (
  SELECT 
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS prescription_duration
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN 
    patient_demographics p ON pr.subject_id = p.subject_id
  WHERE 
    pr.drug_type IS NOT NULL  -- Assuming this filters out non-medication orders
)
SELECT 
  MAX(pd.prescription_duration) AS max_prescription_duration
FROM 
  prescription_durations pd;