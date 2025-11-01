WITH temp_measurements AS (
  SELECT 
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    c.charttime,
    CASE 
      WHEN c.valueuom = 'F' THEN (c.valuenum - 32) * 5.0 / 9.0
      WHEN c.valueuom = 'C' THEN c.valuenum
      ELSE NULL
    END AS temp_celsius
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
    AND LOWER(di.label) LIKE '%temp%'
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.stay_id = i.stay_id
  WHERE c.valuenum IS NOT NULL
    AND (
      (c.valueuom = 'C' AND c.valuenum BETWEEN 20 AND 45) OR
      (c.valueuom = 'F' AND c.valuenum BETWEEN 68 AND 113)
    )
    AND c.charttime >= i.intime
    AND c.charttime < i.intime + INTERVAL 1 DAY
),
stay_averages AS (
  SELECT 
    tm.stay_id,
    AVG(tm.temp_celsius) AS avg_temp
  FROM temp_measurements tm
  GROUP BY tm.stay_id
),
qualified_stays AS (
  SELECT 
    sa.stay_id,
    sa.avg_temp,
    p.gender,
    EXTRACT(YEAR FROM i.intime) - p.anchor_age AS age_at_admission
  FROM stay_averages sa
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON sa.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM i.intime) - p.anchor_age) BETWEEN 67 AND 77
)
SELECT 
  PERCENT_RANK() OVER (ORDER BY avg_temp) * 100 AS percentile_for_36c
FROM qualified_stays
WHERE avg_temp <= 36.0
ORDER BY avg_temp DESC
LIMIT 1;