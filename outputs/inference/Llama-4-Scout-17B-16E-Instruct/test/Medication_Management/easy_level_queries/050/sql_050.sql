WITH prescription_durations AS (
  SELECT 
    pr.subject_id,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS prescription_duration
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm ON pr.hadm_id = adm.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pt ON pr.subject_id = pt.subject_id
  WHERE 
    (LOWER(pr.drug) LIKE '%spironolactone%' OR LOWER(pr.drug) LIKE '%eplerenone%')
    AND pr.stoptime IS NOT NULL
    AND pt.gender = 'M'
    AND EXTRACT(YEAR FROM pt.anchor_age) BETWEEN 64 AND 74
)
SELECT 
  AVG(pd.prescription_duration) AS average_prescription_duration
FROM 
  prescription_durations pd;