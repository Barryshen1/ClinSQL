WITH patient_birth AS (
  SELECT 
    subject_id,
    -- Compute birth date: anchor_year - anchor_age
    DATE_SUB(CAST(CONCAT(anchor_year, '-01-01') AS DATE), INTERVAL anchor_age YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'  -- only females
),
prescription_data AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days,
    TIMESTAMP_DIFF(p.starttime, pb.birth_date, YEAR) AS age_at_prescription
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN patient_birth pb ON p.subject_id = pb.subject_id
  WHERE 
    p.drug IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(p.drug), r'amlodipine|nifedipine|felodipine|isradipine|nicardipine')
    AND p.stoptime IS NOT NULL
    AND p.starttime < p.stoptime  -- ensure positive duration
    AND TIMESTAMP_DIFF(p.starttime, pb.birth_date, YEAR) BETWEEN 59 AND 69
)
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM prescription_data;