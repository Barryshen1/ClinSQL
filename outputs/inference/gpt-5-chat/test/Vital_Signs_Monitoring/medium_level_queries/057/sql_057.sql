WITH male_elderly_icu AS (
  SELECT icu.subject_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 85 AND 95
),
temp_events AS (
  SELECT ce.subject_id, ce.stay_id, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.unitname = '°C'
    AND ce.valuenum IS NOT NULL
),
avg_temp_per_stay AS (
  SELECT me.subject_id, me.stay_id, AVG(te.valuenum) AS avg_temp
  FROM male_elderly_icu me
  JOIN temp_events te
    ON me.subject_id = te.subject_id
   AND me.stay_id = te.stay_id
  GROUP BY me.subject_id, me.stay_id
),
ranked AS (
  SELECT
    stay_id,
    avg_temp,
    PERCENT_RANK() OVER (ORDER BY avg_temp) * 100 AS percentile_rank
  FROM avg_temp_per_stay
)
SELECT DISTINCT
  36.0 AS target_temp,
  percentile_rank
FROM ranked
WHERE ROUND(avg_temp, 3) = 36.000
ORDER BY percentile_rank;