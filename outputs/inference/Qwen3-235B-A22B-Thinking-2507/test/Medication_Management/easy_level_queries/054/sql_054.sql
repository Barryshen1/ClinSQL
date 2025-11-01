SELECT 
  AVG(
    (CASE 
      WHEN p.stoptime IS NOT NULL 
        THEN TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) 
      ELSE TIMESTAMP_DIFF(a.dischtime, p.starttime, SECOND)
    END) / (24 * 60 * 60.0)
  ) AS avg_duration_days
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat 
  ON p.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
  ON p.hadm_id = a.hadm_id
WHERE 
  pat.gender = 'M'
  AND LOWER(p.drug) LIKE '%digoxin%'
  AND (pat.anchor_age + (EXTRACT(YEAR FROM p.starttime) - pat.anchor_year)) BETWEEN 66 AND 76
  AND p.starttime IS NOT NULL
  AND a.dischtime IS NOT NULL
  AND a.dischtime >= p.starttime
  AND (p.stoptime IS NULL OR p.stoptime >= p.starttime);