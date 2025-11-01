WITH eligible_stays AS (
  SELECT i.stay_id, i.intime, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
first_spo2 AS (
  SELECT es.stay_id, c.valuenum AS spo2
  FROM eligible_stays es
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON c.stay_id = es.stay_id
  WHERE c.itemid = 220277
    AND c.charttime >= es.intime
    AND c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 0 AND 100
  QUALIFY ROW_NUMBER() OVER (PARTITION BY es.stay_id ORDER BY c.charttime ASC) = 1
)
SELECT
  APPROX_QUANTILES(spo2, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(spo2, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(spo2, 4)[OFFSET(3)] - APPROX_QUANTILES(spo2, 4)[OFFSET(1)] AS iqr
FROM first_spo2;