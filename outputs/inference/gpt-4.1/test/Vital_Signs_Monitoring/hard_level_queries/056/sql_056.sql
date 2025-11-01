WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 74 AND 84
),

-- Get all relevant measurements in first 48h of ICU stay
measurements AS (
  SELECT
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    c.intime,
    c.outtime,
    c.los,
    ce.charttime,
    -- Bucket by hour
    TIMESTAMP_DIFF(ce.charttime, c.intime, HOUR) AS hour_since_intime,
    ce.itemid,
    ce.valuenum
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (
      223761, 678,         -- Temperature (C, F)
      220277, 646,         -- SpO2
      220210, 618          -- RR
    )
    AND ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),

-- For each stay and hour, flag instability types
instability_by_hour AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    hour_since_intime,
    MAX(CASE
      WHEN itemid IN (223761) AND valuenum > 38.5 THEN 1 -- Temp C > 38.5
      WHEN itemid IN (678) AND ((valuenum - 32) * 5/9) > 38.5 THEN 1 -- Temp F > 38.5C
      ELSE 0 END) AS fever,
    MAX(CASE
      WHEN itemid IN (220277, 646) AND valuenum < 90 THEN 1
      ELSE 0 END) AS hypoxemia,
    MAX(CASE
      WHEN itemid IN (220210, 618) AND valuenum > 20 THEN 1
      ELSE 0 END) AS tachypnea
  FROM
    measurements
  GROUP BY
    stay_id, subject_id, hadm_id, hour_since_intime
),

-- For each stay, count hours with instability types
instability_summary AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    COUNTIF(fever=1 OR hypoxemia=1 OR tachypnea=1) AS instability_hours_48h,
    COUNTIF(fever=1) AS fever_hours_48h,
    COUNTIF(hypoxemia=1) AS hypoxemia_hours_48h,
    COUNTIF(tachypnea=1) AS tachypnea_hours_48h
  FROM
    instability_by_hour
  GROUP BY
    stay_id, subject_id, hadm_id
),

-- Add LOS and mortality
instability_with_outcomes AS (
  SELECT
    s.*,
    c.los,
    a.hospital_expire_flag
  FROM
    instability_summary s
    JOIN cohort c
      ON s.stay_id = c.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON s.hadm_id = a.hadm_id
),

-- Calculate 90th percentile of instability hours
percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_hours_48h, 100)[90] AS instability_90th
  FROM
    instability_with_outcomes
),

-- Select top decile (>= 90th percentile)
top_decile AS (
  SELECT
    i.*
  FROM
    instability_with_outcomes i
    CROSS JOIN percentiles p
  WHERE
    i.instability_hours_48h >= p.instability_90th
)

-- Final output
SELECT
  -- Part 1: 90th percentile value
  (SELECT instability_90th FROM percentiles) AS instability_90th_percentile_hours_48h,

  -- Part 2: Top decile stats
  COUNT(*) AS n_top_decile,
  ROUND(AVG(los)*24,1) AS mean_icu_los_hours,
  ROUND(100*AVG(CAST(hospital_expire_flag AS FLOAT64)),1) AS mortality_percent,
  ROUND(AVG(fever_hours_48h),1) AS mean_fever_hours_48h,
  ROUND(AVG(hypoxemia_hours_48h),1) AS mean_hypoxemia_hours_48h,
  ROUND(AVG(tachypnea_hours_48h),1) AS mean_tachypnea_hours_48h
FROM
  top_decile;