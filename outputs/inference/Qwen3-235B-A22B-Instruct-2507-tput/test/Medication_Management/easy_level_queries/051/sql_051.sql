WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    -- Calculate age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
),
digoxin_prescriptions AS (
  SELECT
    pa.subject_id,
    pr.starttime,
    pr.stoptime,
    -- Duration in hours
    DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) AS duration_hours
  FROM
    patient_admissions pa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
  ON
    pa.subject_id = pr.subject_id
  WHERE
    pa.gender = 'M'
    AND pa.age_at_admit >= 86
    AND pa.age_at_admit <= 96
    AND LOWER(pr.drug) = 'digoxin'
    AND pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND pr.starttime <= pr.stoptime  -- Ensure valid time range
)
SELECT
  -- Calculate IQR: Q3 - Q1
  PERCENTILE_CONT(duration_hours, 0.75) OVER () - PERCENTILE_CONT(duration_hours, 0.25) OVER () AS iqr_duration_hours
FROM
  digoxin_prescriptions
LIMIT 1;