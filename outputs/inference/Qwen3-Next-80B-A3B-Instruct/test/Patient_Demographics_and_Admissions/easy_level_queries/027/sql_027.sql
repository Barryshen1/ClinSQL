WITH first_admissions AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
ranked_first_admissions AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM first_admissions
),
first_admissions_only AS (
  SELECT 
    los_days
  FROM ranked_first_admissions
  WHERE rn = 1
)
SELECT 
  PERCENTILE_CONT(los_days, 0.75) OVER () - PERCENTILE_CONT(los_days, 0.25) OVER () AS iqr_los_days
FROM first_admissions_only
LIMIT 1;