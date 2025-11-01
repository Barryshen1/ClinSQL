WITH spo2_itemids AS (
  -- Identify the itemid(s) corresponding to SpO2 in d_items
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%spo2%'
    OR LOWER(label) LIKE '%oxygen saturation%'
),

female_elderly_stays AS (
  -- Select ICU stays of female patients aged 87–97
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
),

avg_spo2_per_stay AS (
  -- Compute first-24-hour average SpO2 per stay
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    AVG(ce.valuenum) AS avg_spo2_24h
  FROM
    female_elderly_stays f
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON f.subject_id = ce.subject_id
      AND f.hadm_id = ce.hadm_id
      AND f.stay_id = ce.stay_id
    JOIN spo2_itemids di
      ON ce.itemid = di.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum <= 100
    AND ce.charttime <= TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
  GROUP BY
    f.subject_id,
    f.hadm_id,
    f.stay_id
)

-- Final: compute percentile of 88% among these per-stay averages
SELECT
  100.0 * COUNTIF(avg_spo2_24h <= 88) / COUNT(*) AS percentile_of_88
FROM
  avg_spo2_per_stay;