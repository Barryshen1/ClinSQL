WITH sbp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'  -- systolic BP labels
    AND LOWER(category) LIKE '%blood pressure%'
),
sbp_measurements AS (
  SELECT ce.subject_id, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN sbp_itemids si
    ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL
)
SELECT
  PERCENTILE_CONT(sbp.valuenum, 0.75) OVER() AS sbp_75th_percentile
FROM sbp_measurements sbp
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON sbp.subject_id = p.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69;