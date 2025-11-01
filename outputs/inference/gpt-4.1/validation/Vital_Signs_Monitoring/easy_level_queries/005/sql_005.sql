WITH female_59_69 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 59 AND 69
),
sbp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
    OR LOWER(label) LIKE '%sbp%'
    OR LOWER(label) LIKE '%non invasive blood pressure systolic%'
),
sbp_values AS (
  SELECT ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN female_59_69 f ON ce.subject_id = f.subject_id
  JOIN sbp_itemids s ON ce.itemid = s.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 50 AND 300
)
SELECT
  PERCENTILE_CONT(valuenum, 0.75) OVER() AS sbp_75th_percentile
FROM sbp_values;