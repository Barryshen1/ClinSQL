WITH first_map AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS map_value,
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 55 AND 65
    AND di.label LIKE '%mean%arterial%pressure%'
    AND ce.valuenum IS NOT NULL
)
SELECT
  STDDEV_SAMP(map_value) AS stddev_first_map
FROM
  first_map
WHERE
  rn = 1;