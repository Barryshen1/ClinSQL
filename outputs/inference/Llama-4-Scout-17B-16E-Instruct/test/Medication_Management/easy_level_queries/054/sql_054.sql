SELECT 
  AVG(DATE_DIFF(pr.stoptime, pr.starttime, DAY)) AS average_duration_days
FROM 
  `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p 
    ON pr.subject_id = p.subject_id
WHERE 
  p.gender = 'M'
  AND p.anchor_age BETWEEN 66 AND 76
  AND LOWER(pr.drug) LIKE '%digoxin%'
  AND pr.stoptime IS NOT NULL;  -- Ensure we have a valid duration;