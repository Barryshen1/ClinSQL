WITH filtered_prescriptions AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    a.dischtime,
    pat.anchor_age + EXTRACT(YEAR FROM a.admittime) - pat.anchor_year AS age_at_admission,
    DATETIME_DIFF(COALESCE(p.stoptime, a.dischtime), p.starttime, SECOND) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON p.subject_id = pat.subject_id
  WHERE 
    LOWER(p.drug) LIKE '%amiodarone%'
    AND pat.gender = 'F'
    AND (pat.anchor_age + EXTRACT(YEAR FROM a.admittime) - pat.anchor_year) BETWEEN 59 AND 69
    AND p.starttime IS NOT NULL
    AND (p.stoptime IS NOT NULL OR a.dischtime IS NOT NULL)
)
SELECT 
  APPROX_QUANTILES(duration_days, 1000)[OFFSET(750)] - APPROX_QUANTILES(duration_days, 1000)[OFFSET(250)] AS iqr
FROM filtered_prescriptions;