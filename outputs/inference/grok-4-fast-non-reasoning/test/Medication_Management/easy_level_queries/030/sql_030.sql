WITH patient_prescriptions AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) AS duration_hours
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON 
    p.subject_id = pr.subject_id
  WHERE 
    pr.drug = 'Amiodarone'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
),
unique_patient_durations AS (
  SELECT 
    subject_id,
    anchor_age,
    MIN(duration_hours) AS min_duration_hours
  FROM 
    patient_prescriptions
  WHERE 
    duration_hours > 0
  GROUP BY 
    subject_id, anchor_age
)
SELECT 
  PERCENTILE_CONT(min_duration_hours, 0.25) AS p25_duration_hours
FROM 
  unique_patient_durations;