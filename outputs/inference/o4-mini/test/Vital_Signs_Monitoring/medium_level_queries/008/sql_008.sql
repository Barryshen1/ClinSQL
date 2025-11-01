WITH per_stay_map AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    AVG(ce.valuenum) AS avg_map
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.subject_id = ce.subject_id
   AND icu.hadm_id = ce.hadm_id
   AND icu.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND di.label = 'Mean Arterial Pressure'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime < icu.intime + INTERVAL 24 HOUR
  GROUP BY
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
)
SELECT
  100.0 * SUM(CASE WHEN avg_map <= 75 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_of_75_mmHg
FROM
  per_stay_map;