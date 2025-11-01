WITH
-- Identify female patients aged 58-68 on RRT
rrt_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.subject_id = pe.subject_id AND i.hadm_id = pe.hadm_id AND i.stay_id = pe.stay_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND pe.itemid IN (225148, 225149) -- CRRT and HD itemids
),

-- Get vital signs data for first 72 hours
vital_signs AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum,
    TIMESTAMP_DIFF(ce.charttime, i.intime, HOUR) AS hours_since_icu_admission
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    rrt_patients r ON ce.subject_id = r.subject_id AND ce.hadm_id = r.hadm_id AND ce.stay_id = r.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON ce.subject_id = i.subject_id AND ce.hadm_id = i.hadm_id AND ce.stay_id = i.stay_id
  WHERE
    ce.itemid IN (220050, 220045) -- MAP and HR itemids
    AND TIMESTAMP_DIFF(ce.charttime, i.intime, HOUR) <= 72
),

-- Calculate time periods with MAP < 65 and HR > 100
instability_periods AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    SUM(CASE WHEN map_hr_both THEN 1 ELSE 0 END) AS unstable_minutes,
    COUNT(DISTINCT TIMESTAMP_TRUNC(charttime, MINUTE)) AS total_minutes
  FROM (
    SELECT
      vs.subject_id,
      vs.hadm_id,
      vs.stay_id,
      TIMESTAMP_TRUNC(vs.charttime, MINUTE) AS minute_interval,
      MAX(CASE WHEN vs.itemid = 220050 AND vs.valuenum < 65 THEN 1 ELSE 0 END) AS map_low,
      MAX(CASE WHEN vs.itemid = 220045 AND vs.valuenum > 100 THEN 1 ELSE 0 END) AS hr_high,
      CASE WHEN
        MAX(CASE WHEN vs.itemid = 220050 AND vs.valuenum < 65 THEN 1 ELSE 0 END) = 1
        AND MAX(CASE WHEN vs.itemid = 220045 AND vs.valuenum > 100 THEN 1 ELSE 0 END) = 1
      THEN 1 ELSE 0 END AS map_hr_both
    FROM
      vital_signs vs
    GROUP BY
      subject_id, hadm_id, stay_id, TIMESTAMP_TRUNC(vs.charttime, MINUTE)
  )
  GROUP BY
    subject_id, hadm_id, stay_id
),

-- Calculate vital-instability index (percentage of time with both conditions)
instability_index AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    unstable_minutes / NULLIF(total_minutes, 0) AS instability_index
  FROM
    instability_periods
),

-- Get ICU LOS and mortality
outcomes AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  JOIN
    rrt_patients r ON i.subject_id = r.subject_id AND i.hadm_id = r.hadm_id
),

-- Combine all data
final_data AS (
  SELECT
    ii.subject_id,
    ii.hadm_id,
    ii.stay_id,
    ii.instability_index,
    o.icu_los_hours,
    o.hospital_expire_flag
  FROM
    instability_index ii
  JOIN
    outcomes o ON ii.subject_id = o.subject_id AND ii.hadm_id = o.hadm_id AND ii.stay_id = o.stay_id
),

-- Calculate percentiles first
percentiles AS (
  SELECT
    PERCENTILE_CONT(instability_index, 0.25) OVER() AS p25,
    PERCENTILE_CONT(instability_index, 0.5) OVER() AS p50,
    PERCENTILE_CONT(instability_index, 0.75) OVER() AS p75,
    PERCENTILE_CONT(instability_index, 0.9) OVER() AS p90
  FROM
    final_data
  LIMIT 1
)

-- Final results
SELECT
  p.p25 AS p25_instability,
  p.p50 AS p50_instability,
  p.p75 AS p75_instability,
  p.p90 AS p90_instability,
  p.p75 - p.p25 AS iqr_instability,

  CASE
    WHEN fd.instability_index <= p.p25 THEN 'Q1 (low)'
    WHEN fd.instability_index <= p.p50 THEN 'Q2'
    WHEN fd.instability_index <= p.p75 THEN 'Q3'
    ELSE 'Q4 (high)'
  END AS instability_quartile,

  COUNT(*) AS patient_count,
  AVG(fd.icu_los_hours) AS avg_icu_los,
  SUM(fd.hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM
  final_data fd
CROSS JOIN
  percentiles p
GROUP BY
  instability_quartile, p.p25, p.p50, p.p75, p.p90
ORDER BY
  instability_quartile;