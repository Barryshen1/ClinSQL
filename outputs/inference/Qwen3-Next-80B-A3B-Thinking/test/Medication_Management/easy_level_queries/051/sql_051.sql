WITH durations AS (
  SELECT
    TIMESTAMP_DIFF(stoptime, starttime, 'DAY') AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE
    pt.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year + pt.anchor_age) BETWEEN 86 AND 96
    AND LOWER(p.drug) = 'digoxin'
    AND stoptime IS NOT NULL
    AND starttime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY duration_days) -
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration_days) AS iqr
FROM durations;