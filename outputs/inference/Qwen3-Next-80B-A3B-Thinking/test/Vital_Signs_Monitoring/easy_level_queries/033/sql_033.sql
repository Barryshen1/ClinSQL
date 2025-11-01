WITH filtered_data AS (
  SELECT
    c.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND c.itemid = 220045
    AND c.charttime >= i.intime + INTERVAL 24 HOUR
    AND c.charttime <= i.outtime
    AND c.valuenum IS NOT NULL
)
SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS iqr
FROM
  filtered_data;