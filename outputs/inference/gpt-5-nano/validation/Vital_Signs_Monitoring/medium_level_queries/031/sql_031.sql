WITH temp24 AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    AVG(c.valuenum) AS avg_temp_24h
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON c.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON c.itemid = di.itemid
  WHERE LOWER(p.gender) = 'male'
    AND p.anchor_age BETWEEN 67 AND 77
    AND LOWER(di.label) LIKE '%temperature%'
    AND c.charttime >= i.intime
    AND c.charttime <= TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY i.subject_id, i.hadm_id, i.stay_id
  HAVING AVG(c.valuenum) IS NOT NULL
)

SELECT
  100.0 * SUM(CASE WHEN avg_temp_24h <= 36.0 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_of_36C
FROM temp24;