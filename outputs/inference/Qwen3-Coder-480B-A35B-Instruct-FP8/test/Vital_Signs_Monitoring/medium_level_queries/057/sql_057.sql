WITH temp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
    AND linksto = 'chartevents'
),

filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 85 AND 95
),

icu_temp_averages AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS avg_temp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN filtered_patients fp ON ce.subject_id = fp.subject_id
  JOIN temp_itemids ti ON ce.itemid = ti.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 20 AND 45
  GROUP BY ce.stay_id
),

percentile_ranks AS (
  SELECT 
    avg_temp,
    PERCENT_RANK() OVER (ORDER BY avg_temp) AS percentile_rank
  FROM icu_temp_averages
)

SELECT 
  MAX(CASE WHEN avg_temp = 36.0 THEN percentile_rank END) AS percentile_rank_of_36C
FROM percentile_ranks;