WITH ccb_prescriptions AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    LOWER(pr.drug) AS drug,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON a.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND (
      LOWER(pr.drug) LIKE '%amlodipine%' OR
      LOWER(pr.drug) LIKE '%nifedipine%' OR
      LOWER(pr.drug) LIKE '%felodipine%' OR
      LOWER(pr.drug) LIKE '%isradipine%' OR
      LOWER(pr.drug) LIKE '%nicardipine%' OR
      LOWER(pr.drug) LIKE '%nimodipine%' OR
      LOWER(pr.drug) LIKE '%clevidipine%'
    )
)

SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS percentile_25_duration_days
FROM
  ccb_prescriptions
WHERE
  duration_days IS NOT NULL;