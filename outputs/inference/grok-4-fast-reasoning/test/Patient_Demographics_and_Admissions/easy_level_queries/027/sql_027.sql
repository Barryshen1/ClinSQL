WITH first_adms AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    a.dischtime IS NOT NULL
),
ranked_adms AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
  FROM 
    first_adms
)
SELECT 
  PERCENTILE_CONT(los_days, 0.25) OVER() AS q1_days,
  PERCENTILE_CONT(los_days, 0.75) OVER() AS q3_days,
  (PERCENTILE_CONT(los_days, 0.75) OVER() - PERCENTILE_CONT(los_days, 0.25) OVER()) AS iqr_days
FROM 
  ranked_adms
WHERE 
  rn = 1
  AND gender = 'F'
  AND age_at_adm >= 77
  AND age_at_adm <= 87;