WITH durations AS (
  SELECT 
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.hadm_id = a.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat ON p.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND LOWER(p.drug) LIKE '%amiodarone%'
    AND p.hadm_id IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    AND (pat.anchor_age + EXTRACT(YEAR FROM a.admittime) - pat.anchor_year) BETWEEN 42 AND 52
)
SELECT 
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS p25_duration_days
FROM 
  durations;