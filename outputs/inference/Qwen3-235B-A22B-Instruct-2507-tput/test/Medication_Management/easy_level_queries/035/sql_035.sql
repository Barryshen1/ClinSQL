SELECT 
  MAX(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR)) AS max_duration_hours
FROM 
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON pr.subject_id = p.subject_id
WHERE 
  p.gender = 'F'
  -- Estimate age at prescription time
  AND (p.anchor_age + (EXTRACT(YEAR FROM pr.starttime) - p.anchor_year)) BETWEEN 80 AND 90
  -- Filter for nitrate drugs: nitroglycerin or isosorbide
  AND (
    (LOWER(pr.drug) LIKE '%nitro%' AND LOWER(pr.drug) LIKE '%glycer%')
    OR LOWER(pr.drug) LIKE '%isosorbide%'
  )
  -- Filter for IV, oral, sublingual routes
  AND UPPER(pr.route) IN ('IV', 'PO', 'SL')
  -- Ensure valid duration
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL
  AND pr.stoptime >= pr.starttime;