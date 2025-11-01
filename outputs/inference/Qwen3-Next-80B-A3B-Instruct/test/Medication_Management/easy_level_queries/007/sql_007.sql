WITH thiazide_prescriptions AS (
  SELECT 
    p.subject_id,
    p.stoptime,
    p.starttime,
    p.drug,
    -- Compute duration in days as a FLOAT
    EXTRACT(DAY FROM (p.stoptime - p.starttime)) AS duration_days
  FROM 
    physionet-data.mimiciv_3_1_hosp.prescriptions p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients pt
    ON p.subject_id = pt.subject_id
  WHERE 
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 90 AND 100
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime >= p.starttime
    AND (
      LOWER(p.drug) LIKE '%hydrochlorothiazide%'
      OR LOWER(p.drug) LIKE '%chlorthalidone%'
      OR LOWER(p.drug) LIKE '%metolazone%'
      OR LOWER(p.drug) LIKE '%indapamide%'
    )
),
iqr_calc AS (
  SELECT
    PERCENTILE_CONT(duration_days, 0.25) OVER () AS q1,
    PERCENTILE_CONT(duration_days, 0.75) OVER () AS q3
  FROM thiazide_prescriptions
  WHERE duration_days > 0
)
SELECT
  q3 - q1 AS iqr_days
FROM iqr_calc
LIMIT 1;