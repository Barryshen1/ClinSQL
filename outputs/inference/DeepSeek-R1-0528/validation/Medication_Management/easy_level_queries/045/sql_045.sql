WITH cohort AS (
  SELECT 
      p.subject_id, 
      p.gender, 
      p.anchor_age, 
      p.anchor_year,
      a.hadm_id,
      a.admittime,
      -- Calculate age at admission
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    -- Filter for age 57-67 at admission
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 57 AND 67
),
dapt_prescriptions AS (
  SELECT 
      pr.subject_id,
      pr.hadm_id,
      pr.drug,
      pr.starttime,
      pr.stoptime,
      -- Calculate duration in fractional days
      CAST(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) AS FLOAT64) / 24.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN cohort c
      ON pr.subject_id = c.subject_id
      AND pr.hadm_id = c.hadm_id
  WHERE 
      -- Identify DAPT drugs (case-insensitive match)
      (LOWER(pr.drug) LIKE '%aspirin%' OR 
       LOWER(pr.drug) LIKE '%acetylsalicylic acid%' OR 
       LOWER(pr.drug) LIKE '%clopidogrel%' OR 
       LOWER(pr.drug) LIKE '%plavix%' OR 
       LOWER(pr.drug) LIKE '%ticagrelor%' OR 
       LOWER(pr.drug) LIKE '%brilinta%' OR 
       LOWER(pr.drug) LIKE '%prasugrel%' OR 
       LOWER(pr.drug) LIKE '%effient%')
      -- Exclude invalid durations
      AND pr.stoptime IS NOT NULL
      AND pr.stoptime >= pr.starttime
),
quantiles AS (
  SELECT APPROX_QUANTILES(duration_days, 100) AS q
  FROM dapt_prescriptions
)
SELECT 
  q[OFFSET(25)] AS q1,
  q[OFFSET(75)] AS q3,
  q[OFFSET(75)] - q[OFFSET(25)] AS iqr
FROM quantiles;