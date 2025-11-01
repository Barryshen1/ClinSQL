WITH eligible_patients AS (
  SELECT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
spo2_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%' OR LOWER(label) LIKE '%o2 saturation%'
),
first_spo2 AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.stay_id,
    MIN(c.charttime) AS first_charttime
  FROM
    eligible_patients e
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
      ON e.subject_id = c.subject_id
      AND e.stay_id = c.stay_id
      AND c.charttime >= e.intime
      AND c.charttime <= e.intime + INTERVAL 6 HOUR
    INNER JOIN spo2_itemids s
      ON c.itemid = s.itemid
  GROUP BY
    e.subject_id, e.hadm_id, e.stay_id
),
first_spo2_value AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    c.valuenum AS spo2_value
  FROM
    first_spo2 f
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
      ON f.subject_id = c.subject_id
      AND f.stay_id = c.stay_id
      AND c.charttime = f.first_charttime
    INNER JOIN spo2_itemids s
      ON c.itemid = s.itemid
  WHERE
    c.valuenum IS NOT NULL
)
SELECT
  APPROX_QUANTILES(spo2_value, 4)[OFFSET(1)] AS spo2_25th_percentile,
  APPROX_QUANTILES(spo2_value, 4)[OFFSET(3)] AS spo2_75th_percentile,
  APPROX_QUANTILES(spo2_value, 4)[OFFSET(3)] - APPROX_QUANTILES(spo2_value, 4)[OFFSET(1)] AS spo2_IQR
FROM
  first_spo2_value
;