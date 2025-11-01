WITH selected_stays AS (
  SELECT
    cs.stay_id,
    cs.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` cs
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON cs.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
spo2_events AS (
  SELECT
    ss.stay_id,
    ce.valuenum AS spo2,
    ROW_NUMBER() OVER (PARTITION BY ss.stay_id ORDER BY ce.charttime) AS rn
  FROM selected_stays ss
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = ss.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= ss.intime
    AND ce.valuenum IS NOT NULL
    AND (
      LOWER(di.label) LIKE '%oxygen saturation%'
      OR LOWER(di.abbreviation) LIKE '%spo2%'
    )
),
first_spo2_per_stay AS (
  SELECT
    stay_id,
    spo2 AS first_spo2
  FROM spo2_events
  WHERE rn = 1
),
spo2_values AS (
  SELECT
    first_spo2
  FROM first_spo2_per_stay
  WHERE first_spo2 IS NOT NULL
)
SELECT
  quantiles[OFFSET(25)] AS p25_spo2,
  quantiles[OFFSET(75)] AS p75_spo2,
  quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS iqr_spo2
FROM (
  SELECT
    APPROX_QUANTILES(first_spo2, 100) AS quantiles
  FROM spo2_values
);