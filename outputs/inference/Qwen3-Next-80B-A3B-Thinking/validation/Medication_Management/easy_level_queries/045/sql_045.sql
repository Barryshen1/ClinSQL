WITH durations AS (
  SELECT
    DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON
    p.subject_id = pt.subject_id
  WHERE
    pt.gender = 'M'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year)) BETWEEN 57 AND 67
    AND (
      LOWER(p.drug) LIKE '%aspirin%'
      OR LOWER(p.drug) LIKE '%acetylsalicylic acid%'
      OR LOWER(p.drug) LIKE '%asa%'
      OR LOWER(p.drug) LIKE '%clopidogrel%'
      OR LOWER(p.drug) LIKE '%prasugrel%'
      OR LOWER(p.drug) LIKE '%ticagrelor%'
    )
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime > p.starttime
)
SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr
FROM
  durations;