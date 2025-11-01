WITH map_items AS (
  -- identify itemids corresponding to Mean Arterial Pressure (MAP)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
     OR LOWER(label) LIKE '%mean arterial pressure (%'
     OR LOWER(label) LIKE '%map%'
     OR LOWER(abbreviation) = 'map'
),
map_events AS (
  -- numeric MAP measurements
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.storetime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN map_items mi
    ON ce.itemid = mi.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime IS NOT NULL
),
map_after_intime AS (
  -- restrict to MAP events that occur during the ICU stay (on or after intime)
  SELECT
    me.subject_id,
    me.hadm_id,
    me.stay_id,
    me.charttime,
    me.storetime,
    me.valuenum
  FROM map_events me
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON me.subject_id = icu.subject_id
   AND me.hadm_id = icu.hadm_id
   AND me.stay_id = icu.stay_id
  WHERE me.charttime >= icu.intime
    AND me.charttime <= icu.outtime
),
first_map_per_stay AS (
  -- pick the first MAP measurement on ICU admission for each stay
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    valuenum AS map_val
  FROM (
    SELECT
      m.*,
      ROW_NUMBER() OVER (PARTITION BY m.stay_id ORDER BY m.charttime ASC, m.storetime ASC) AS rn
    FROM map_after_intime m
  )
  WHERE rn = 1
),
eligible_first_maps AS (
  -- restrict to male patients aged 55-65
  SELECT
    f.*
  FROM first_map_per_stay f
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON f.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
)
-- final result: count and sample standard deviation of first MAP on ICU admission
SELECT
  COUNT(*) AS n_stays,
  STDDEV_SAMP(map_val) AS sd_first_map
FROM eligible_first_maps;