WITH durations AS (
  SELECT 
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON 
    p.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND p.hadm_id IS NOT NULL
    AND p.drug_type <> 'Discharge'
    AND (
      LOWER(p.drug) LIKE '%amlodipine%'
      OR LOWER(p.drug) LIKE '%nifedipine%'
      OR LOWER(p.drug) LIKE '%felodipine%'
      OR LOWER(p.drug) LIKE '%nicardipine%'
      OR LOWER(p.drug) LIKE '%nimodipine%'
    )
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
)
SELECT 
  APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM 
  durations;