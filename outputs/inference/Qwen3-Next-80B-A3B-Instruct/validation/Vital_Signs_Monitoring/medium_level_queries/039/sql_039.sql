WITH eligible_patients AS (
  SELECT p.subject_id, i.stay_id, i.intime
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
),
map_measurements AS (
  SELECT e.stay_id, c.valuenum, c.charttime
  FROM eligible_patients e
  JOIN physionet-data.mimiciv_3_1_icu.chartevents c
    ON e.stay_id = c.stay_id
  JOIN physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  WHERE d.label = 'Mean Arterial Pressure'
    AND c.valuenum IS NOT NULL
    AND c.charttime >= e.intime
    AND c.charttime <= DATETIME_ADD(e.intime, INTERVAL 48 HOUR)
),
per_stay_avg AS (
  SELECT stay_id,
         AVG(valuenum) AS avg_map,
         COUNT(*) AS measurement_count
  FROM map_measurements
  GROUP BY stay_id
  HAVING COUNT(*) >= 3
)
SELECT 
  CASE 
    WHEN COUNT(*) = 0 THEN NULL
    ELSE COUNTIF(avg_map <= 60) * 100.0 / COUNT(*)
  END AS percentile
FROM per_stay_avg;