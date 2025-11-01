WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 62 AND 72
),
amiodarone_durations AS (
  SELECT 
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) / 86400.0 AS duration_days
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ep.subject_id = pr.subject_id AND ep.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%amiodarone%'
    AND pr.stoptime IS NOT NULL
    AND pr.starttime <= pr.stoptime
)
SELECT 
  APPROX_QUANTILES(duration_days, 1000)[OFFSET(750)] 
  - APPROX_QUANTILES(duration_days, 1000)[OFFSET(250)] AS iqr
FROM amiodarone_durations;