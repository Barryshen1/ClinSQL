WITH spo2_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%oxygen saturation%'
    OR LOWER(label) LIKE '%spo2%'
    OR LOWER(abbreviation) LIKE '%spo2%'
),

icustay_spo2 AS (
  SELECT
    icu.subject_id,
    icu.stay_id,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.subject_id = ce.subject_id
    AND icu.stay_id    = ce.stay_id
  JOIN
    spo2_items AS si
    ON ce.itemid = si.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime
                        AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
),

patient_means AS (
  SELECT
    subject_id,
    stay_id,
    AVG(valuenum) AS mean_spo2
  FROM
    icustay_spo2
  GROUP BY
    subject_id,
    stay_id
),

eligible AS (
  SELECT
    pm.subject_id,
    pm.stay_id,
    pm.mean_spo2
  FROM
    patient_means AS pm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON pm.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON pm.subject_id = icu.subject_id
    AND pm.stay_id    = icu.stay_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
)

SELECT
  92.0 AS target_mean_spo2,
  SAFE_DIVIDE(
    COUNTIF(mean_spo2 <= 92.0),
    COUNT(*)
  ) AS percentile
FROM
  eligible;