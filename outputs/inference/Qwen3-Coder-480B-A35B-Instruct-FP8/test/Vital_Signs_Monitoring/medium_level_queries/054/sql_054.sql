WITH sbp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
    AND linksto = 'chartevents'
),

filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 87 AND 97
),

sbp_first24 AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN filtered_patients fp ON ce.subject_id = fp.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.stay_id = icu.stay_id
  JOIN sbp_itemids sbp ON ce.itemid = sbp.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY ce.stay_id
),

sbp_percentiles AS (
  SELECT
    avg_sbp,
    PERCENT_RANK() OVER (ORDER BY avg_sbp) AS percentile_rank
  FROM sbp_first24
)

SELECT
  MAX(CASE WHEN avg_sbp <= 150 THEN percentile_rank ELSE NULL END) AS percentile_of_150
FROM sbp_percentiles;