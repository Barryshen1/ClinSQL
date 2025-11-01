SELECT 
  APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM (
  SELECT 
    TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) / 86400.0 AS duration_days
  FROM 
    physionet-data.mimiciv_3_1_hosp.prescriptions p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON p.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 58 AND 68
    AND (
      LOWER(p.drug) LIKE '%heparin%' 
      OR LOWER(p.drug) LIKE '%enoxaparin%' 
      OR LOWER(p.drug) LIKE '%lovenox%'
    )
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
) AS filtered_prescriptions;