WITH filtered_prescriptions AS (
  SELECT
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    p.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 58 AND 68
    AND (LOWER(p.drug) LIKE '%heparin%' OR LOWER(p.drug) LIKE '%enoxaparin%')
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
)
SELECT
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration) AS median_duration
FROM
  filtered_prescriptions;