WITH MAP_MEAN_PER_STAY AS (
  SELECT
    ci.subject_id,
    ci.hadm_id,
    ci.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ci
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = ci.subject_id
   AND ce.hadm_id = ci.hadm_id
   AND ce.stay_id = ci.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ce.itemid
  WHERE
    (LOWER(di.label) LIKE '%mean arterial pressure%')
    AND ce.charttime >= ci.intime
    AND ce.charttime < TIMESTAMP_ADD(ci.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ci.subject_id, ci.hadm_id, ci.stay_id
  HAVING
    AVG(ce.valuenum) IS NOT NULL
),
COHORT AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    m.mean_map
  FROM MAP_MEAN_PER_STAY AS m
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = m.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
)
SELECT
  CAST(100.0 * SUM(CASE WHEN mean_map <= 85 THEN 1 ELSE 0 END) / COUNT(*) AS FLOAT64) AS percentile_of_85_in_cohort
FROM COHORT;