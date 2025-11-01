WITH patient_age AS (
  SELECT 
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
),
warfarin_prescriptions AS (
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM 
    patient_age pa
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON pa.hadm_id = pr.hadm_id
  WHERE 
    pa.gender = 'M'
    AND pa.age_at_admission BETWEEN 43 AND 53
    AND LOWER(pr.drug) LIKE '%warfarin%'
)
SELECT 
  AVG(duration_days) AS avg_duration_days
FROM 
  warfarin_prescriptions;