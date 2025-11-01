WITH durations AS (
  SELECT
    DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE
    pt.gender = 'M'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year)) BETWEEN 62 AND 72
    AND LOWER(p.drug) = 'amiodarone'
    AND p.stoptime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] - APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS iqr_days
FROM durations;