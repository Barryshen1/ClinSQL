SELECT
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration_days) AS percentile_25
FROM (
  SELECT
    DATE_DIFF(
      LEAST(COALESCE(p.stoptime, a.dischtime), a.dischtime),
      p.starttime,
      'DAY'
    ) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 42 AND 52
    AND LOWER(p.drug) LIKE '%amiodarone%'
    AND p.starttime IS NOT NULL
    AND p.starttime <= COALESCE(p.stoptime, a.dischtime)
);