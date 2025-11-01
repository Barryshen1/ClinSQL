WITH population_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 86 AND 96
),
atorvastatin_prescriptions AS (
  SELECT 
    pr.hadm_id,
    GREATEST(pr.starttime, pa.admittime) AS start_time,
    LEAST(pr.stoptime, pa.dischtime) AS end_time
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN population_admissions pa
    ON pr.hadm_id = pa.hadm_id
  WHERE LOWER(pr.drug) LIKE '%atorvastatin%'
    AND pr.dose_val_rx IS NOT NULL
    AND LOWER(pr.dose_unit_rx) = 'mg'
    AND pr.doses_per_24_hrs IS NOT NULL
    AND SAFE_CAST(pr.dose_val_rx AS FLOAT64) IS NOT NULL
    AND SAFE_CAST(pr.doses_per_24_hrs AS FLOAT64) IS NOT NULL
    AND (SAFE_CAST(pr.dose_val_rx AS FLOAT64) * SAFE_CAST(pr.doses_per_24_hrs AS FLOAT64)) BETWEEN 40 AND 80
    AND GREATEST(pr.starttime, pa.admittime) < LEAST(pr.stoptime, pa.dischtime)
),
base AS (
  SELECT 
    hadm_id,
    start_time,
    end_time
  FROM atorvastatin_prescriptions
),
ordered AS (
  SELECT 
    hadm_id,
    start_time,
    end_time,
    LAG(end_time) OVER (PARTITION BY hadm_id ORDER BY start_time) AS prev_end
  FROM base
),
groups AS (
  SELECT 
    hadm_id,
    start_time,
    end_time,
    SUM(CASE WHEN start_time <= prev_end THEN 0 ELSE 1 END) OVER (PARTITION BY hadm_id ORDER BY start_time) AS grp
  FROM ordered
),
merged_intervals AS (
  SELECT 
    hadm_id,
    MIN(start_time) AS start_time,
    MAX(end_time) AS end_time
  FROM groups
  GROUP BY hadm_id, grp
),
total_duration AS (
  SELECT 
    hadm_id,
    SUM(TIMESTAMP_DIFF(end_time, start_time, SECOND)) / (24 * 60 * 60) AS total_duration_days
  FROM merged_intervals
  GROUP BY hadm_id
)
SELECT 
  MIN(total_duration_days) AS min_duration_days
FROM total_duration;