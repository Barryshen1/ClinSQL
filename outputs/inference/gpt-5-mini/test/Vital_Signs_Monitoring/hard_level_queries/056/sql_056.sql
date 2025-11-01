WITH
-- Cohort: male ICU patients age 74-84 with a hemorrhagic-stroke diagnosis in the admission
cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON i.subject_id = p.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON i.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = i.hadm_id
        AND (
          LOWER(d.long_title) LIKE '%hemorrhag%'   -- hemorrhage / hemorrhagic
          OR LOWER(d.long_title) LIKE '%intracerebral%'
          OR LOWER(d.long_title) LIKE '%subarachnoid%'
          OR LOWER(d.long_title) LIKE '%ich%'       -- common abbreviation
        )
    )
),

-- Identify itemids for temperature, SpO2, and respiratory rate using d_items label heuristics
temp_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temp%' OR LOWER(label) LIKE '%temperature%'
),
spo2_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%' OR LOWER(label) LIKE '%o2 sat%' OR LOWER(label) LIKE '%oxygen saturation%' OR LOWER(label) LIKE '%oximetry%'
),
rr_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%' OR LOWER(label) LIKE '%resp rate%' OR LOWER(label) = 'rr'
),

-- Gather relevant chartevents in first 48 hours and flag per event if they meet thresholds
events_flagged AS (
  SELECT
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    -- hour offset from ICU intime: 0..47
    CAST(FLOOR(TIMESTAMP_DIFF(c.charttime, coh.intime, SECOND) / 3600.0) AS INT64) AS hour_offset,
    -- flags per event row (0/1)
    CASE
      WHEN t.itemid IS NOT NULL AND c.valuenum IS NOT NULL AND c.valuenum > 38.5 THEN 1
      ELSE 0
    END AS is_fever,
    CASE
      WHEN s.itemid IS NOT NULL AND c.valuenum IS NOT NULL AND c.valuenum < 90 THEN 1
      ELSE 0
    END AS is_hypoxemia,
    CASE
      WHEN r.itemid IS NOT NULL AND c.valuenum IS NOT NULL AND c.valuenum > 20 THEN 1
      ELSE 0
    END AS is_tachypnea
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN cohort coh
      ON c.stay_id = coh.stay_id
    LEFT JOIN temp_items t
      ON c.itemid = t.itemid
    LEFT JOIN spo2_items s
      ON c.itemid = s.itemid
    LEFT JOIN rr_items r
      ON c.itemid = r.itemid
  WHERE
    c.charttime IS NOT NULL
    AND c.charttime >= coh.intime
    AND c.charttime < TIMESTAMP_ADD(coh.intime, INTERVAL 48 HOUR)
    AND (t.itemid IS NOT NULL OR s.itemid IS NOT NULL OR r.itemid IS NOT NULL)
    AND TIMESTAMP_DIFF(c.charttime, coh.intime, SECOND) >= 0
),

-- Reduce to one row per (stay_id, hour_offset) and set whether that hour had any flagged measurements
hours_per_stay AS (
  SELECT
    ef.stay_id,
    ef.subject_id,
    ef.hadm_id,
    ef.hour_offset,
    MAX(ef.is_fever) AS hour_fever_flag,
    MAX(ef.is_hypoxemia) AS hour_hypoxemia_flag,
    MAX(ef.is_tachypnea) AS hour_tachypnea_flag,
    CASE WHEN MAX(ef.is_fever) = 1 OR MAX(ef.is_hypoxemia) = 1 OR MAX(ef.is_tachypnea) = 1 THEN 1 ELSE 0 END AS hour_any_flag
  FROM events_flagged ef
  GROUP BY ef.stay_id, ef.subject_id, ef.hadm_id, ef.hour_offset
),

-- Aggregate per stay: hours in first 48h for each condition and any instability
per_stay_summary AS (
  SELECT
    hps.stay_id,
    hps.subject_id,
    hps.hadm_id,
    SUM(hps.hour_fever_flag) AS hours_fever,
    SUM(hps.hour_hypoxemia_flag) AS hours_hypoxemia,
    SUM(hps.hour_tachypnea_flag) AS hours_tachypnea,
    SUM(hps.hour_any_flag) AS hours_any
  FROM hours_per_stay hps
  GROUP BY hps.stay_id, hps.subject_id, hps.hadm_id
),

-- join back to cohort to include stays with zero flagged hours (those may be absent from per_stay_summary)
all_stays AS (
  SELECT
    coh.*,
    COALESCE(ps.hours_fever, 0) AS hours_fever,
    COALESCE(ps.hours_hypoxemia, 0) AS hours_hypoxemia,
    COALESCE(ps.hours_tachypnea, 0) AS hours_tachypnea,
    COALESCE(ps.hours_any, 0) AS hours_any
  FROM cohort coh
  LEFT JOIN per_stay_summary ps
    ON coh.stay_id = ps.stay_id
),

-- compute 90th percentile of hours_any across the cohort
p90 AS (
  SELECT
    APPROX_QUANTILES(hours_any, 100)[OFFSET(90)] AS p90_hours_any
  FROM all_stays
),

-- select top decile stays (hours_any >= 90th percentile)
top_decile AS (
  SELECT
    s.*,
    p.p90_hours_any
  FROM all_stays s
  CROSS JOIN p90 p
  WHERE s.hours_any >= p.p90_hours_any
)

-- Final output: 90th percentile value and stats for the top decile
SELECT
  p.p90_hours_any AS hours_any_90th_percentile,
  COUNT(t.stay_id) AS top_decile_n,
  ROUND(AVG(t.los), 2) AS mean_icu_los_days,
  ROUND(100.0 * AVG(CAST(t.hospital_expire_flag AS FLOAT64)), 1) AS mortality_percent,
  ROUND(AVG(t.hours_fever), 2) AS mean_hours_fever,
  ROUND(AVG(t.hours_hypoxemia), 2) AS mean_hours_hypoxemia,
  ROUND(AVG(t.hours_tachypnea), 2) AS mean_hours_tachypnea
FROM top_decile t
CROSS JOIN p90 p
GROUP BY p.p90_hours_any;