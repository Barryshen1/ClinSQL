WITH arb_prescriptions AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    a.dischtime,
    -- Compute duration: if stoptime is not null, use it; else use dischtime (if within admission)
    CASE 
      WHEN p.stoptime IS NOT NULL THEN 
        EXTRACT(DAY FROM (p.stoptime - p.starttime))
      WHEN a.dischtime IS NOT NULL AND p.starttime <= a.dischtime THEN 
        EXTRACT(DAY FROM (a.dischtime - p.starttime))
      ELSE NULL 
    END AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pt 
    ON p.subject_id = pt.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE 
    pt.gender = 'M'
    AND pt.anchor_age BETWEEN 38 AND 48
    AND LOWER(p.drug) LIKE '%sartan%'
    AND p.starttime IS NOT NULL
    AND (p.stoptime IS NOT NULL OR a.dischtime IS NOT NULL)
    AND p.starttime <= COALESCE(p.stoptime, a.dischtime)
)
SELECT 
  PERCENTILE_CONT(duration_days, 0.75) WITHIN GROUP (ORDER BY duration_days) AS p75_duration_days
FROM 
  arb_prescriptions
WHERE 
  duration_days IS NOT NULL
  AND duration_days >= 0;