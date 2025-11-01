WITH sbp_averages AS (
  SELECT
    icustays.subject_id,
    AVG(chartevents.valuenum) AS avg_sbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` chartevents
    ON icustays.stay_id = chartevents.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d_items
    ON chartevents.itemid = d_items.itemid
  WHERE
    patients.gender = 'F'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year)) BETWEEN 45 AND 55
    AND d_items.label LIKE '%Systolic%'
    AND chartevents.charttime >= icustays.intime
    AND chartevents.charttime <= icustays.intime + INTERVAL 24 HOUR
    AND chartevents.valuenum IS NOT NULL
  GROUP BY icustays.subject_id, icustays.stay_id
)
SELECT
  CASE
    WHEN avg_sbp < 140 THEN '<140'
    WHEN avg_sbp BETWEEN 140 AND 159 THEN '140-159'
    ELSE '>=160'
  END AS sbp_category,
  COUNT(DISTINCT subject_id) AS count
FROM sbp_averages
GROUP BY sbp_category;