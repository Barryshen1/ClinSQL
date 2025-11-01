WITH cohort AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON ic.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON ic.subject_id = a.subject_id
     AND ic.hadm_id    = a.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
),

events_first48 AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    FLOOR(TIMESTAMP_DIFF(ce.charttime, c.intime, MINUTE) / 60) AS hour_offset,
    CASE
      WHEN LOWER(di.label) LIKE '%temp%' AND ce.valuenum > 38.5 THEN 1
      ELSE 0
    END AS is_fever,
    CASE
      WHEN LOWER(di.label) LIKE '%spo2%' AND ce.valuenum < 90 THEN 1
      ELSE 0
    END AS is_hypoxemia,
    CASE
      WHEN (LOWER(di.label) LIKE '%respiratory%' OR LOWER(di.label) LIKE '%rr%')
           AND ce.valuenum > 20 THEN 1
      ELSE 0
    END AS is_tachypnea
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.subject_id = ce.subject_id
     AND c.hadm_id    = ce.hadm_id
     AND c.stay_id    = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
),

per_hour_flags AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    hour_offset,
    GREATEST(MAX(is_fever), MAX(is_hypoxemia), MAX(is_tachypnea)) AS is_instable,
    MAX(is_fever)     AS hour_fever,
    MAX(is_hypoxemia) AS hour_hypoxemia,
    MAX(is_tachypnea) AS hour_tachypnea
  FROM events_first48
  WHERE hour_offset BETWEEN 0 AND 47
  GROUP BY subject_id, hadm_id, stay_id, hour_offset
),

per_stay_summary AS (
  SELECT
    ph.subject_id,
    ph.hadm_id,
    ph.stay_id,
    COUNTIF(is_instable = 1)   AS instability_hours,
    SUM(hour_fever)            AS hours_fever,
    SUM(hour_hypoxemia)        AS hours_hypoxemia,
    SUM(hour_tachypnea)        AS hours_tachypnea
  FROM per_hour_flags ph
  GROUP BY ph.subject_id, ph.hadm_id, ph.stay_id
),

p90 AS (
  -- compute the 90th percentile cutoff for instability hours
  SELECT
    APPROX_QUANTILES(instability_hours, 10)[OFFSET(9)] AS p90_instability_hours
  FROM per_stay_summary
),

top_decile AS (
  -- select stays at or above the 90th percentile
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.instability_hours,
    s.hours_fever,
    s.hours_hypoxemia,
    s.hours_tachypnea
  FROM per_stay_summary s
  CROSS JOIN p90
  WHERE s.instability_hours >= p90.p90_instability_hours
)

SELECT
  COUNT(*)                                  AS n_top_decile,
  ROUND(AVG(c.los), 2)                      AS mean_icu_los_days,
  ROUND(100 * AVG(c.hospital_expire_flag),1) AS mortality_percent,
  ROUND(AVG(t.hours_fever), 1)              AS mean_hours_fever,
  ROUND(AVG(t.hours_hypoxemia), 1)          AS mean_hours_hypoxemia,
  ROUND(AVG(t.hours_tachypnea), 1)          AS mean_hours_tachypnea
FROM top_decile t
JOIN cohort c
  ON t.subject_id = c.subject_id
 AND t.hadm_id    = c.hadm_id
 AND t.stay_id    = c.stay_id;