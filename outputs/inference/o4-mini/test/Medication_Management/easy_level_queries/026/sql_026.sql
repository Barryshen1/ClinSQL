WITH durations AS (
  SELECT
    DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 81 AND 91
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND DATE(p.stoptime) >= DATE(p.starttime)
    AND LOWER(p.drug) IN (
      'amlodipine',
      'nifedipine',
      'felodipine',
      'nicardipine',
      'isradipine',
      'nisoldipine',
      'lercanidipine'
    )
)
SELECT
  quantiles[OFFSET(1)] AS p25_duration_days
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quantiles
  FROM durations
);