SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM (
  SELECT
    DATETIME_DIFF(pres.stoptime, pres.starttime, SECOND) / (24 * 60 * 60) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.prescriptions pres
  ON
    pat.subject_id = pres.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 58 AND 68
    AND LOWER(pres.drug) LIKE '%heparin%'
    OR LOWER(pres.drug) LIKE '%enoxaparin%'
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
)
WHERE
  duration_days >= 0  -- Ensure non-negative durations;