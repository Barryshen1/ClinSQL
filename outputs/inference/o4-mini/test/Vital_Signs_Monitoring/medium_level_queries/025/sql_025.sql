WITH temp_per_stay AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    AVG(e.valuenum) AS avg_temp
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON s.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS e
    ON s.subject_id = e.subject_id
   AND s.hadm_id    = e.hadm_id
   AND s.stay_id    = e.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS d
    ON e.itemid = d.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND LOWER(d.label) LIKE '%temperature%'
    AND e.valuenum IS NOT NULL
    AND e.charttime BETWEEN s.intime
                       AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  GROUP BY
    s.subject_id,
    s.hadm_id,
    s.stay_id
),
stats AS (
  SELECT
    COUNT(*) AS total_stays,
    SUM(CASE WHEN avg_temp <= 37.5 THEN 1 ELSE 0 END) AS stays_leq_37_5
  FROM
    temp_per_stay
)
SELECT
  100.0 * stays_leq_37_5 / total_stays AS percentile_of_37_5
FROM
  stats;