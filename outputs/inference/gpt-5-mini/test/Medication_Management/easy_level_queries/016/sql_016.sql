WITH cohort AS (
  -- male inpatients aged 76-86 (anchor_age used as the age indicator)
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
),
nitrate_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug,
    pr.route,
    -- duration in days (fractional)
    SAFE_DIVIDE(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND), 86400.0) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN
    cohort c
  ON
    pr.subject_id = c.subject_id
    AND pr.hadm_id = c.hadm_id
  WHERE
    pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    -- ensure the prescription start is during the inpatient admission
    AND pr.starttime >= c.admittime
    AND pr.starttime <= c.dischtime
    -- drug name filters for common nitrates (case-insensitive)
    AND (
      LOWER(pr.drug) LIKE '%nitroglycerin%'
      OR LOWER(pr.drug) LIKE '%isosorbide%'
      OR LOWER(pr.drug) LIKE '%nitroprusside%'
      OR LOWER(pr.drug) LIKE '%nitrate%'
    )
    -- route filter: include IV and common oral routes (case-insensitive)
    AND (
      REGEXP_CONTAINS(IFNULL(pr.route, ''), r'(?i)\b(iv|intravenous)\b')
      OR REGEXP_CONTAINS(IFNULL(pr.route, ''), r'(?i)\b(po|oral|sublingual|sl)\b')
    )
    -- sensible durations only
    AND SAFE_DIVIDE(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND), 86400.0) >= 0
)
SELECT
  -- extract the 25th percentile (first quartile) of prescription durations (days)
  quantiles[OFFSET(1)] AS p25_duration_days
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quantiles
  FROM
    nitrate_prescriptions
);