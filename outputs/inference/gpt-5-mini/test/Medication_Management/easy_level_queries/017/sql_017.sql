WITH warfarin_rx AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    (UNIX_SECONDS(CAST(pr.stoptime AS TIMESTAMP)) - UNIX_SECONDS(CAST(pr.starttime AS TIMESTAMP))) / 86400.0
      AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON pr.subject_id = pt.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.hadm_id = a.hadm_id
    AND pr.subject_id = a.subject_id
  WHERE pt.gender = 'M'
    AND pt.anchor_age BETWEEN 43 AND 53
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND (
      LOWER(pr.drug) LIKE '%warfarin%'
      OR LOWER(pr.drug) LIKE '%coumadin%'
    )
    -- ensure the prescription start occurs during the hospital admission
    AND CAST(pr.starttime AS TIMESTAMP) >= CAST(a.admittime AS TIMESTAMP)
    AND CAST(pr.starttime AS TIMESTAMP) <= CAST(a.dischtime AS TIMESTAMP)
)
SELECT
  COUNT(*) AS n_prescriptions,
  AVG(duration_days) AS avg_duration_days,
  STDDEV(duration_days) AS sd_duration_days,
  APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM warfarin_rx
WHERE duration_days > 0;