WITH
map_events AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    ce.charttime,
    ce.valuenum AS map_value
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON icu.subject_id = ce.subject_id
     AND icu.hadm_id    = ce.hadm_id
     AND icu.stay_id    = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND di.label = 'Mean Arterial Pressure'
    AND ce.charttime BETWEEN icu.intime
                        AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),
stay_map_stats AS (
  SELECT
    stay_id,
    COUNT(*)    AS n_measurements,
    AVG(map_value) AS avg_map
  FROM map_events
  GROUP BY stay_id
  HAVING COUNT(*) >= 3
),
percentile_calc AS (
  SELECT
    COUNTIF(avg_map <= 60) AS num_le_60,
    COUNT(*)              AS total_stays
  FROM stay_map_stats
)
SELECT
  100.0 * SAFE_DIVIDE(num_le_60, total_stays) AS percentile_of_60
FROM percentile_calc;