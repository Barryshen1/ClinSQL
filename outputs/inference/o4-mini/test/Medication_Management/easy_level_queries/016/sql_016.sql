SELECT
  quantiles[OFFSET(25)] AS p25_duration_days
FROM (
  SELECT
    APPROX_QUANTILES(
      DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY),
      100
    ) AS quantiles
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON pt.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON a.subject_id = p.subject_id
     AND a.hadm_id = p.hadm_id
  WHERE
    pt.gender = 'M'
    AND pt.anchor_age BETWEEN 76 AND 86
    AND p.starttime BETWEEN a.admittime AND a.dischtime
    AND p.stoptime IS NOT NULL
    -- Filter for nitrates
    AND (
      LOWER(p.drug) LIKE '%nitroglycerin%'
      OR LOWER(p.drug) LIKE '%isosorbide%'
      OR LOWER(p.drug) LIKE '%nitrate%'
    )
    -- IV or oral routes
    AND (
      LOWER(p.route) LIKE '%iv%'
      OR LOWER(p.route) LIKE '%intravenous%'
      OR LOWER(p.route) LIKE '%oral%'
      OR LOWER(p.route) LIKE '%po%'
    )
);