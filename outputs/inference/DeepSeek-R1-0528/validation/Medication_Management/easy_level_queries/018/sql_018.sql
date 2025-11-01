WITH eligible_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id,
    -- Calculate age at admission using anchor_year and admittime
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'  -- Filter for males
),
digoxin_prescriptions AS (
  SELECT 
    pr.starttime,
    pr.stoptime,
    -- Calculate duration in fractional days (handles partial days)
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN eligible_admissions ea
    ON pr.subject_id = ea.subject_id
    AND pr.hadm_id = ea.hadm_id
  WHERE 
    LOWER(pr.drug) LIKE '%digoxin%'  -- Case-insensitive digoxin search
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime  -- Ensure valid duration
    AND ea.age_at_admission BETWEEN 82 AND 92  -- Age filter
)
-- Return the maximum prescription duration
SELECT MAX(duration_days) AS max_duration_days
FROM digoxin_prescriptions;