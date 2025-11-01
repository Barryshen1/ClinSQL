WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
),
dapt_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    CASE
      WHEN LOWER(pr.drug) LIKE '%aspirin%' THEN 'aspirin'
      WHEN LOWER(pr.drug) LIKE '%clopidogrel%' THEN 'p2y12'
      WHEN LOWER(pr.drug) LIKE '%ticagrelor%' THEN 'p2y12'
      WHEN LOWER(pr.drug) LIKE '%prasugrel%' THEN 'p2y12'
      ELSE NULL
    END AS dapt_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE
    LOWER(pr.drug) LIKE '%aspirin%'
    OR LOWER(pr.drug) LIKE '%clopidogrel%'
    OR LOWER(pr.drug) LIKE '%ticagrelor%'
    OR LOWER(pr.drug) LIKE '%prasugrel%'
),
dapt_admissions AS (
  -- Only admissions with both aspirin and p2y12 prescribed
  SELECT
    c.subject_id,
    c.hadm_id
  FROM
    cohort c
    INNER JOIN dapt_prescriptions dp ON c.subject_id = dp.subject_id AND c.hadm_id = dp.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id
  HAVING
    COUNT(DISTINCT dp.dapt_class) = 2
),
dapt_durations AS (
  -- For each DAPT admission, get earliest start and latest stop among DAPT drugs
  SELECT
    da.subject_id,
    da.hadm_id,
    MIN(dp.starttime) AS dapt_start,
    MAX(dp.stoptime) AS dapt_stop,
    DATETIME_DIFF(MAX(dp.stoptime), MIN(dp.starttime), DAY) AS dapt_duration_days
  FROM
    dapt_admissions da
    INNER JOIN dapt_prescriptions dp
      ON da.subject_id = dp.subject_id AND da.hadm_id = dp.hadm_id
  WHERE
    dp.dapt_class IN ('aspirin', 'p2y12')
    AND dp.starttime IS NOT NULL
    AND dp.stoptime IS NOT NULL
  GROUP BY
    da.subject_id, da.hadm_id
)
SELECT
  quantiles[OFFSET(1)] AS iqr_25th_percentile_days,
  quantiles[OFFSET(3)] AS iqr_75th_percentile_days,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_days
FROM (
  SELECT
    APPROX_QUANTILES(dapt_duration_days, 4) AS quantiles
  FROM
    dapt_durations
);