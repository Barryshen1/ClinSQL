WITH eligible_prescriptions AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime,
    DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) AS duration_days,
    pat.gender,
    pat.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND p.drug_type = 'INPATIENT'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    AND (
      LOWER(p.drug) LIKE '%amlodipine%'
      OR LOWER(p.drug) LIKE '%nifedipine%'
      OR LOWER(p.drug) LIKE '%felodipine%'
      OR LOWER(p.drug) LIKE '%nicardipine%'
      OR LOWER(p.drug) LIKE '%nimodipine%'
      OR LOWER(p.drug) LIKE '%isradipine%'
      OR LOWER(p.drug) LIKE '%clevidipine%'
    )
)

SELECT 
  PERCENTILE_CONT(duration_days, 0.25) AS p25_duration_days
FROM 
  eligible_prescriptions
WHERE 
  duration_days > 0;