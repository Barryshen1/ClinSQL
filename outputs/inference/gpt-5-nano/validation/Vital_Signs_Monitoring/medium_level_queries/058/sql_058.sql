WITH per_stay AS (
  SELECT
    icu.stay_id,
    AVG(ce.valuenum) AS systolic_avg
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    AND LOWER(di.label) LIKE '%systolic%'
    AND ce.valuenum IS NOT NULL
  GROUP BY icu.stay_id
)
SELECT
  SAFE_DIVIDE(
    SUM(CASE WHEN systolic_avg <= 120 THEN 1 ELSE 0 END),
    COUNT(*)
  ) * 100 AS percentile_of_120
FROM per_stay
WHERE systolic_avg IS NOT NULL;