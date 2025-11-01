SELECT 
  AVG(TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY)) AS avg_prescription_duration_days
FROM 
  physionet-data.mimiciv_3_1_hosp.prescriptions p
JOIN 
  physionet-data.mimiciv_3_1_hosp.patients pat
  ON p.subject_id = pat.subject_id
WHERE 
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 64 AND 74
  AND LOWER(p.drug) IN ('spironolactone', 'eplerenone')
  AND p.stoptime IS NOT NULL;