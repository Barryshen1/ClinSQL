WITH nitrate_prescriptions AS (
  SELECT 
    TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) / 86400.0 AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat 
    ON p.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 76 AND 86
    AND p.hadm_id IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.starttime < p.stoptime
    AND (
      LOWER(p.drug) LIKE '%nitroglycerin%' 
      OR LOWER(p.drug) LIKE '%isosorbide%'
    )
    AND p.route IN ('IV', 'PO', 'SL')
)
SELECT 
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS p25_duration_days
FROM 
  nitrate_prescriptions
WHERE 
  duration_days > 0;