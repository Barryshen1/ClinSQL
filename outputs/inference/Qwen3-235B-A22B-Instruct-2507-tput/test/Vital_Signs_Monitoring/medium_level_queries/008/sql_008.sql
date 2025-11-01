WITH patient_age AS (
  SELECT
    p.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays i
  ON
    p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 39 AND 49
),
map_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE (LOWER(label) LIKE '%arterial pressure mean%'
    OR LOWER(label) LIKE '%map%')
    AND LOWER(category) = 'vital signs'
  ORDER BY itemid
  LIMIT 1
),
map_first_24h AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_map
  FROM
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays i
  ON
    ce.stay_id = i.stay_id
  CROSS JOIN
    map_item
  INNER JOIN
    patient_age pa
  ON
    ce.subject_id = pa.subject_id
  WHERE
    ce.itemid = map_item.itemid
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime <= DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY
    ce.stay_id
)
SELECT
  SUM(CASE WHEN avg_map <= 75 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile_rank_of_75
FROM
  map_first_24h;