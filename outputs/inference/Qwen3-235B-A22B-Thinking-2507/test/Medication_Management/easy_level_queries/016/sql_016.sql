WITH nitrate_prescriptions AS (
  SELECT
    DATETIME_DIFF(pr.stoptime, pr.starttime, SECOND) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
  WHERE
    -- Age 76-86 at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 76 AND 86
    -- Nitrate drugs (case-insensitive)
    AND (
      LOWER(pr.drug) LIKE '%nitroglycerin%'
      OR LOWER(pr.drug) LIKE '%isosorbide dinitrate%'
      OR LOWER(pr.drug) LIKE '%isosorbide mononitrate%'
    )
    -- IV or oral routes (case-insensitive)
    AND (
      LOWER(pr.route) LIKE '%iv%'
      OR LOWER(pr.route) LIKE '%intravenous%'
      OR LOWER(pr.route) LIKE '%oral%'
      OR LOWER(pr.route) LIKE '%po%'
    )
    -- Valid duration (non-NULL stoptime and positive duration)
    AND pr.stoptime IS NOT NULL
    AND pr.starttime <= pr.stoptime
)
SELECT
  PERCENTILE_CONT(duration_days, 0.25) OVER () AS percentile_25
FROM nitrate_prescriptions
LIMIT 1;