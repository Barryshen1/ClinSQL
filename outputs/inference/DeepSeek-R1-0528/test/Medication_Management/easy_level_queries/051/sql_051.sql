WITH filtered_prescriptions AS (
  SELECT
    DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt 
    ON p.subject_id = pt.subject_id
  WHERE
    pt.gender = 'M'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year)) BETWEEN 86 AND 96
    AND LOWER(p.drug) LIKE '%digoxin%'
    AND p.stoptime IS NOT NULL
    AND p.stoptime >= p.starttime
)
SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr
FROM filtered_prescriptions;