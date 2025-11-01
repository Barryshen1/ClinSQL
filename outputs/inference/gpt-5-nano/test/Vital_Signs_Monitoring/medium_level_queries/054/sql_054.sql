WITH per_stay AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    AVG(CAST(c.valuenum AS FLOAT64)) AS first24h_avg_sbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON c.subject_id = i.subject_id
   AND c.hadm_id = i.hadm_id
   AND c.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = c.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND LOWER(di.label) LIKE '%systolic%'
    AND c.charttime >= i.intime
    AND c.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
    AND c.valuenum IS NOT NULL
  GROUP BY i.subject_id, i.hadm_id, i.stay_id
  HAVING AVG(CAST(c.valuenum AS FLOAT64)) IS NOT NULL
)

SELECT
  SAFE_DIVIDE(SUM(IF(first24h_avg_sbp <= 150, 1, 0)), COUNT(*)) * 100 AS percentile_150
FROM per_stay;