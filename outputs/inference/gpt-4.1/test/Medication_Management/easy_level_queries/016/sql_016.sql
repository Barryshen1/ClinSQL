WITH nitrate_prescriptions AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug,
    pr.route,
    -- Duration in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND), 86400) AS duration_days
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON pr.subject_id = a.subject_id AND pr.hadm_id = a.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 76 AND 86
    AND p.gender = 'M'
    -- Nitrate drugs: nitroglycerin, isosorbide dinitrate, isosorbide mononitrate, etc.
    AND (
      LOWER(pr.drug) LIKE '%nitroglycerin%' OR
      LOWER(pr.drug) LIKE '%isosorbide dinitrate%' OR
      LOWER(pr.drug) LIKE '%isosorbide mononitrate%' OR
      LOWER(pr.drug) LIKE '%nitrate%'
    )
    -- Route: IV or oral
    AND (
      LOWER(pr.route) LIKE '%iv%' OR
      LOWER(pr.route) LIKE '%intravenous%' OR
      LOWER(pr.route) LIKE '%oral%'
    )
    -- Valid duration
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
)
SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS percentile_25_duration_days
FROM
  nitrate_prescriptions
WHERE
  duration_days > 0
;