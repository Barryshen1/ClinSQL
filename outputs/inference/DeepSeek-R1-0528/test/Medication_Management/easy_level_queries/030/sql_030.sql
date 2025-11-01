SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_duration_days
FROM (
  SELECT
    -- Calculate duration in fractional days
    DATETIME_DIFF(p.stoptime, p.starttime, HOUR) / 24.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE
    LOWER(p.drug) LIKE '%amiodarone%'  -- Case-insensitive amiodarone match
    AND p.stoptime IS NOT NULL         -- Exclude ongoing prescriptions
    AND pt.gender = 'F'                -- Females
    -- Age at admission: 42–52 years
    AND (pt.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year) 
         BETWEEN 42 AND 52)
);