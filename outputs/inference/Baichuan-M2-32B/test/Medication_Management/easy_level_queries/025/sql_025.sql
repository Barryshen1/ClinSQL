WITH patients_with_birth AS (
  SELECT 
    subject_id,
    gender,
    anchor_year,
    anchor_age,
    DATE_SUB(CAST(CONCAT(anchor_year, '-01-01') AS DATE), INTERVAL anchor_age YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
),
admissions_with_age AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.gender,
    FLOOR(DATE_DIFF(a.admittime, p.birth_date, DAY) / 365.25) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_with_birth p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'  -- male
    AND FLOOR(DATE_DIFF(a.admittime, p.birth_date, DAY) / 365.25) BETWEEN 62 AND 72
),
amiodarone_prescriptions AS (
  SELECT 
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN admissions_with_age aa 
    ON pr.subject_id = aa.subject_id AND pr.hadm_id = aa.hadm_id
  WHERE LOWER(pr.drug) LIKE '%amiodarone%'  -- case-insensitive match
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime  -- ensure stoptime is after starttime
)
SELECT 
  APPROX_QUANTILES(duration_days, 1000)[OFFSET(750)] - APPROX_QUANTILES(duration_days, 1000)[OFFSET(250)] AS iqr
FROM amiodarone_prescriptions;