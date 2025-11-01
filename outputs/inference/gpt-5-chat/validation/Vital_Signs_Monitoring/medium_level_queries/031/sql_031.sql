WITH temp_data AS (
  SELECT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    AVG(c.valuenum) AS avg_temp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON i.subject_id = c.subject_id
    AND i.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON c.itemid = di.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND di.label LIKE '%Temperature%'
    AND di.unitname = '°C'
    AND c.valuenum IS NOT NULL
    AND c.charttime >= i.intime
    AND c.charttime < DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY p.subject_id, i.hadm_id, i.stay_id
),
counts AS (
  SELECT
    COUNTIF(avg_temp <= 36.0) AS le_count,
    COUNT(*) AS total_count
  FROM temp_data
)
SELECT
  le_count,
  total_count,
  ROUND(100.0 * le_count / total_count, 2) AS percentile_le_36C
FROM counts;