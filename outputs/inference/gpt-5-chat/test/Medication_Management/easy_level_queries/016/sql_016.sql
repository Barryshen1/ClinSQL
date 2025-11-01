WITH nitrate_rx AS (
  SELECT
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id
  WHERE p.anchor_age BETWEEN 76 AND 86
    AND LOWER(p.gender) = 'male'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) >= 0
    AND (
      LOWER(pr.drug) LIKE '%nitrate%'
      OR LOWER(pr.drug) LIKE '%nitroglycerin%'
      OR LOWER(pr.drug) LIKE '%isosorbide%'
    )
    AND (
      LOWER(pr.route) LIKE '%iv%'
      OR LOWER(pr.route) LIKE '%intravenous%'
      OR LOWER(pr.route) LIKE '%oral%'
      OR LOWER(pr.route) LIKE '%po%'
    )
)
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS p25_duration_days
FROM nitrate_rx;