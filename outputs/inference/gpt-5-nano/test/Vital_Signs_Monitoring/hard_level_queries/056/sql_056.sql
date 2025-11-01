WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    s.stay_id,
    s.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS s
    ON a.hadm_id = s.hadm_id AND p.subject_id = s.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
),
hourly AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    TIMESTAMP_TRUNC(ce.charttime, HOUR) AS hour_ts,
    MAX(CASE WHEN LOWER(di.label) LIKE '%temperature%' AND ce.valuenum > 38.5 THEN 1 ELSE 0 END) AS fever_present,
    MAX(CASE WHEN (LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%oxygen saturation%') AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS hypox_present,
    MAX(CASE WHEN (LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%rr%') AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS tachy_present
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id = c.hadm_id
   AND ce.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, hour_ts
),
per_stay AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.stay_id,
    SUM(CASE WHEN h.fever_present = 1 OR h.hypox_present = 1 OR h.tachy_present = 1 THEN 1 ELSE 0 END) AS unstable_hours,
    SUM(h.fever_present) AS fever_hours,
    SUM(h.hypox_present) AS hypox_hours,
    SUM(h.tachy_present) AS tachy_hours,
    s.los,
    a.hospital_expire_flag
  FROM hourly AS h
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS s
    ON h.subject_id = s.subject_id
   AND h.hadm_id = s.hadm_id
   AND h.stay_id = s.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON s.hadm_id = a.hadm_id AND s.subject_id = a.subject_id
  GROUP BY h.subject_id, h.hadm_id, h.stay_id, s.los, a.hospital_expire_flag
),
p90 AS (
  -- Compute 90th percentile of unstable_hours using APPROX_QUANTILES
  SELECT q[OFFSET(90)] AS p90
  FROM (
    SELECT APPROX_QUANTILES(unstable_hours, 100) AS q
    FROM per_stay
  )
),
top_decile AS (
  SELECT ps.*
  FROM per_stay AS ps
  CROSS JOIN p90
  WHERE ps.unstable_hours >= p90.p90
)
SELECT
  COUNT(*) AS n,
  AVG(los) AS mean_icu_los,
  (SUM(CAST(hospital_expire_flag AS FLOAT64)) / NULLIF(COUNT(*), 0)) * 100 AS mortality_percent,
  AVG(fever_hours) AS mean_hours_fever,
  AVG(hypox_hours) AS mean_hours_hypox,
  AVG(tachy_hours) AS mean_hours_tachy
FROM top_decile;