WITH first24h_map AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    AVG(e.valuenum) AS mean_map
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON s.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` e
      ON s.subject_id = e.subject_id
     AND s.hadm_id    = e.hadm_id
     AND s.stay_id    = e.stay_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
    AND e.itemid = 52  -- MAP
    AND e.valuenum IS NOT NULL
    AND e.charttime BETWEEN s.intime
                       AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  GROUP BY
    s.subject_id,
    s.hadm_id,
    s.stay_id
)
SELECT
  STDDEV_POP(mean_map) AS stddev_first_24h_mean_map
FROM
  first24h_map;