WITH FirstMAP AS (
  SELECT
    p.subject_id,
    ce.valuenum AS first_map,
    i.label AS item_label
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p ON icu.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON icu.subject_id = ce.subject_id AND icu.hadm_id = ce.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS i ON ce.itemid = i.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND i.label LIKE '%MAP%'
    AND ce.charttime >= icu.intime
    AND ce.charttime < icu.intime + INTERVAL '1' HOUR
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY ce.charttime ASC) = 1
)
SELECT
  STDDEV(first_map)
FROM
  FirstMAP;