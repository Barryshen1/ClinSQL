WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
),
antiplatelet_rx AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    CASE
      WHEN LOWER(pr.drug) LIKE '%aspirin%' THEN 'aspirin'
      WHEN LOWER(pr.drug) LIKE '%clopidogrel%' THEN 'p2y12'
      WHEN LOWER(pr.drug) LIKE '%prasugrel%' THEN 'p2y12'
      WHEN LOWER(pr.drug) LIKE '%ticagrelor%' THEN 'p2y12'
      WHEN LOWER(pr.drug) LIKE '%cangrelor%' THEN 'p2y12'
      ELSE NULL
    END AS antiplatelet_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE
    (
      LOWER(pr.drug) LIKE '%aspirin%'
      OR LOWER(pr.drug) LIKE '%clopidogrel%'
      OR LOWER(pr.drug) LIKE '%prasugrel%'
      OR LOWER(pr.drug) LIKE '%ticagrelor%'
      OR LOWER(pr.drug) LIKE '%cangrelor%'
    )
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
),
combo_admissions AS (
  SELECT
    c.subject_id,
    c.hadm_id
  FROM
    cohort c
    INNER JOIN antiplatelet_rx ar ON c.subject_id = ar.subject_id AND c.hadm_id = ar.hadm_id
  GROUP BY
    c.subject_id,
    c.hadm_id
  HAVING
    COUNT(DISTINCT CASE WHEN ar.antiplatelet_type = 'aspirin' THEN 1 END) > 0
    AND COUNT(DISTINCT CASE WHEN ar.antiplatelet_type = 'p2y12' THEN 1 END) > 0
),
rx_duration AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    MIN(DATE(ar.starttime)) AS earliest_start,
    MAX(DATE(ar.stoptime)) AS latest_stop,
    DATE_DIFF(MAX(DATE(ar.stoptime)), MIN(DATE(ar.starttime)), DAY) + 1 AS duration_days
  FROM
    combo_admissions ca
    INNER JOIN antiplatelet_rx ar ON ca.subject_id = ar.subject_id AND ca.hadm_id = ar.hadm_id
  GROUP BY
    ca.subject_id,
    ca.hadm_id
)
SELECT
  PERCENTILE_CONT(duration_days, 0.5) OVER() AS median_antiplatelet_duration_days
FROM
  rx_duration
WHERE
  duration_days IS NOT NULL
;