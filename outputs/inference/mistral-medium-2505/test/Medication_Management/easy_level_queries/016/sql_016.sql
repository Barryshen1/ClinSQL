WITH nitrate_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.route,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 76 AND 86
    AND (
      LOWER(p.drug) LIKE '%nitrate%'
      OR LOWER(p.drug_type) LIKE '%nitrate%'
    )
    AND p.route IN ('IV', 'ORAL')
    AND p.stoptime IS NOT NULL
)

SELECT
  PERCENTILE_CONT(duration_days, 0.25) OVER() AS percentile_25_duration_days
FROM
  nitrate_prescriptions
LIMIT 1;