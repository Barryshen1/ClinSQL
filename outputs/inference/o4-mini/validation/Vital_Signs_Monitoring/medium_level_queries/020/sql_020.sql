WITH female_icustays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
),

map_item AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) = 'mean arterial pressure'
),

mean_map_per_stay AS (
  SELECT
    f.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM
    female_icustays AS f
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON f.subject_id = ce.subject_id
      AND f.hadm_id    = ce.hadm_id
      AND f.stay_id    = ce.stay_id
    JOIN map_item AS mi
      ON ce.itemid = mi.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN f.intime
                       AND DATETIME_ADD(f.intime, INTERVAL 48 HOUR)
  GROUP BY
    f.stay_id
),

percentile_calc AS (
  SELECT
    COUNTIF(mean_map <= 85) AS num_at_or_below_85,
    COUNT(*)                 AS total_stays
  FROM
    mean_map_per_stay
)

SELECT
  100.0 * SAFE_DIVIDE(num_at_or_below_85, total_stays) AS percentile_of_85_mmHg
FROM
  percentile_calc;