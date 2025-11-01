WITH spo2_items AS (
  -- find itemids likely to represent SpO2 / oxygen saturation
  SELECT DISTINCT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
     OR LOWER(label) LIKE '%o2 sat%'
     OR LOWER(label) LIKE '%oxygen saturation%'
     OR LOWER(label) LIKE '%sao2%'
     OR LOWER(label) LIKE '%pulse oxim%'
),
spo2_readings AS (
  -- numeric SpO2 readings from ICU chart events, limited to reasonable range
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN spo2_items di
    ON ce.itemid = di.itemid
  WHERE ce.stay_id IS NOT NULL
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 1 AND 100
),
per_stay_mean AS (
  -- per-ICU-stay mean SpO2
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    AVG(sr.valuenum) AS mean_spo2
  FROM spo2_readings sr
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` s
    USING(subject_id, hadm_id, stay_id)
  GROUP BY s.subject_id, s.hadm_id, s.stay_id
),
filtered_stays AS (
  -- restrict to female patients aged 38-48 (anchor_age)
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    m.mean_spo2,
    p.gender,
    p.anchor_age
  FROM per_stay_mean m
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
)
-- final summary: count and percentile (proportion <= 92%)
SELECT
  COUNT(*) AS n_stays,
  SUM(CASE WHEN mean_spo2 <= 92 THEN 1 ELSE 0 END) AS n_stays_mean_le_92,
  SAFE_DIVIDE(SUM(CASE WHEN mean_spo2 <= 92 THEN 1 ELSE 0 END), COUNT(*)) * 100.0 AS percentile_le_92
FROM filtered_stays;