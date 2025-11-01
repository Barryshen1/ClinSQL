WITH rrt_patients AS (
  -- Identify RRT patients using inputevents or procedureevents
  SELECT DISTINCT
    ie.subject_id,
    ie.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ie.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%rrt%'
    OR LOWER(di.label) LIKE '%dialysis%'
    OR LOWER(di.label) LIKE '%crrt%'
),

vitals AS (
  -- Extract HR and MAP from chartevents
  SELECT
    ce.stay_id,
    ce.charttime,
    MAX(CASE WHEN di.label LIKE '%Heart Rate%' THEN ce.valuenum END) AS heart_rate,
    MAX(CASE WHEN di.label LIKE '%MAP%' THEN ce.valuenum END) AS map
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.charttime IS NOT NULL
    AND ce.valuenum IS NOT NULL
    AND di.label IN (
      'Heart Rate',
      'MAP',
      'Mean Airway Pressure',
      'Mean arterial pressure',
      'Arterial Line MAP',
      'Non Invasive Blood Pressure mean'
    )
  GROUP BY ce.stay_id, ce.charttime
),

vitals_first72h AS (
  -- Filter vitals to first 72 hours of ICU stay
  SELECT
    v.stay_id,
    v.charttime,
    v.heart_rate,
    v.map
  FROM vitals v
  JOIN rrt_patients r
    ON v.stay_id = r.stay_id
  WHERE v.charttime >= r.intime
    AND v.charttime <= DATETIME_ADD(r.intime, INTERVAL 72 HOUR)
),

instability_events AS (
  -- Identify instability events (HR > 100 and MAP < 65)
  SELECT
    stay_id,
    charttime,
    CASE WHEN heart_rate > 100 AND map < 65 THEN 1 ELSE 0 END AS is_instability
  FROM vitals_first72h
  WHERE heart_rate IS NOT NULL AND map IS NOT NULL
),

instability_summary AS (
  -- Aggregate instability per stay
  SELECT
    stay_id,
    COUNT(*) AS total_obs,
    SUM(is_instability) AS unstable_obs,
    SAFE_DIVIDE(SUM(is_instability), COUNT(*)) AS instability_index,
    SUM(CASE WHEN is_instability = 1 THEN 1 ELSE 0 END) AS unstable_hours
  FROM instability_events
  GROUP BY stay_id
),

patient_demographics AS (
  -- Join with patients and admissions to get age, gender, and mortality
  SELECT
    r.stay_id,
    r.los,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM rrt_patients r
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON r.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON r.subject_id = a.subject_id
),

combined_data AS (
  -- Combine instability and demographics
  SELECT
    pd.stay_id,
    pd.los,
    pd.hospital_expire_flag,
    pd.gender,
    pd.anchor_age,
    COALESCE(isum.instability_index, 0) AS instability_index,
    COALESCE(isum.unstable_hours, 0) AS unstable_hours,
    CASE
      WHEN pd.gender = 'F' AND pd.anchor_age BETWEEN 58 AND 68 THEN 'Target'
      ELSE 'Other'
    END AS group_category
  FROM patient_demographics pd
  LEFT JOIN instability_summary isum
    ON pd.stay_id = isum.stay_id
  WHERE isum.instability_index IS NOT NULL -- Only patients with vitals data
)

-- Final summary: percentiles and group comparison
SELECT
  group_category,
  APPROX_QUANTILES(instability_index, 4)[OFFSET(1)] AS q25_index,
  APPROX_QUANTILES(instability_index, 4)[OFFSET(2)] AS median_index,
  APPROX_QUANTILES(instability_index, 4)[OFFSET(3)] AS q75_index,
  APPROX_QUANTILES(instability_index, 10)[OFFSET(9)] AS p90_index,
  AVG(instability_index) AS mean_index,
  STDDEV(instability_index) AS stddev_index,
  AVG(unstable_hours) AS avg_unstable_hours,
  AVG(los) AS avg_icu_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM combined_data
GROUP BY group_category
ORDER BY group_category;