WITH
-- Identify MAP itemids
map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%map%'
),

-- Filter ICU stays for male patients aged 38-48
eligible_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
),

-- Gather MAP measurements for those stays
stay_map_values AS (
  SELECT
    ce.stay_id,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN map_items mi
    ON ce.itemid = mi.itemid
  WHERE
    ce.stay_id IN (SELECT stay_id FROM eligible_stays)
    AND ce.valuenum IS NOT NULL
    AND LOWER(ce.valueuom) = 'mmhg'
),

-- Compute per-stay average MAP
stay_avg_map AS (
  SELECT
    stay_id,
    AVG(valuenum) AS avg_map
  FROM stay_map_values
  GROUP BY stay_id
),

-- Combine with eligible stays (to exclude stays without MAP measurements)
filtered_stays AS (
  SELECT
    es.stay_id,
    sam.avg_map
  FROM eligible_stays es
  JOIN stay_avg_map sam
    ON es.stay_id = sam.stay_id
),

-- Compute percentile rank
summary AS (
  SELECT
    COUNT(*) AS total_stays,
    SUM(CASE WHEN avg_map <= 60 THEN 1 ELSE 0 END) AS stays_le_60
  FROM filtered_stays
)

SELECT
  stays_le_60 / total_stays AS percentile_rank_le_60
FROM summary;