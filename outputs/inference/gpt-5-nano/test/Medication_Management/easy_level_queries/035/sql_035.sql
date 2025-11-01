WITH nitrate_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.route,
    pr.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = pr.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'Female'
    AND p.anchor_age BETWEEN 80 AND 90
    AND (
      LOWER(pr.drug) LIKE '%nitro%'
      OR LOWER(pr.drug) LIKE '%nitroglycerin%'
      OR LOWER(pr.drug) LIKE '%isosorbide%'
    )
    AND (
      LOWER(pr.route) IN ('iv','po','sl')
      OR LOWER(pr.route) LIKE 'iv%'
      OR LOWER(pr.route) LIKE 'po%'
      OR LOWER(pr.route) LIKE 'sl%'
    )
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
)

SELECT
  ROUND(MAX(TIMESTAMP_DIFF(stoptime, starttime, SECOND) / 3600.0), 2) AS max_nitrate_duration_hours
FROM nitrate_prescriptions;