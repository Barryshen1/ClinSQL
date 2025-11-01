WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 42 AND 52
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
),
amiodarone_prescriptions AS (
  SELECT 
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
  INNER JOIN filtered_admissions a
    ON pr.hadm_id = a.hadm_id
  WHERE 
    LOWER(pr.drug) LIKE '%amiodarone%'
    AND pr.starttime IS NOT NULL
),
clipped_durations AS (
  SELECT 
    hadm_id,
    GREATEST(starttime, admittime) AS start_clip,
    LEAST(COALESCE(stoptime, dischtime), dischtime) AS end_clip
  FROM amiodarone_prescriptions
  WHERE LEAST(COALESCE(stoptime, dischtime), dischtime) > GREATEST(starttime, admittime)
),
total_durations AS (
  SELECT 
    hadm_id,
    SUM(DATETIME_DIFF(end_clip, start_clip, SECOND)) / (24 * 3600.0) AS total_duration_days
  FROM clipped_durations
  GROUP BY hadm_id
  HAVING total_duration_days > 0
)
SELECT 
  APPROX_QUANTILES(total_duration_days, 1000)[OFFSET(250)] AS percentile_25_duration_days
FROM total_durations;