WITH per_stay_avg_temp AS (
  SELECT
    ie.stay_id,
    AVG(ce.valuenum) AS avg_temp
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND ce.itemid = 223762  -- Temperature Celsius
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ie.intime
    AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY
    ie.stay_id
)
SELECT
  (COUNTIF(avg_temp <= 36.0) / COUNT(*)) * 100 AS percentile
FROM
  per_stay_avg_temp;