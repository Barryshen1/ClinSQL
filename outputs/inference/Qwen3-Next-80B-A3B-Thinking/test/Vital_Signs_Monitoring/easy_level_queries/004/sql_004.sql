WITH temp_means AS (
  SELECT
    i.stay_id,
    AVG(c.valuenum) AS mean_temp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    c.itemid = 678
    AND p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 37 AND 47
  GROUP BY
    i.stay_id
)
SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY mean_temp) AS percentile_75
FROM
  temp_means;