WITH amio_durations AS (
  SELECT 
    DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pt 
    ON p.subject_id = pt.subject_id
  WHERE 
    pt.gender = 'M'
    AND (EXTRACT(YEAR FROM p.starttime) - (pt.anchor_year - pt.anchor_age)) BETWEEN 62 AND 72
    AND LOWER(p.drug) LIKE '%amiodarone%'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
),
quartiles AS (
  SELECT 
    APPROX_QUANTILES(duration_days, 4) AS arr
  FROM 
    amio_durations
)
SELECT 
  arr[OFFSET(1)] AS q1,
  arr[OFFSET(3)] AS q3,
  arr[OFFSET(3)] - arr[OFFSET(1)] AS iqr
FROM 
  quartiles;