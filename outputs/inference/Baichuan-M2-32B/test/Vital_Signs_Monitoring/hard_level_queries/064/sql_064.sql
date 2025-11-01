WITH patient_dob AS (
  SELECT
    subject_id,
    -- If anchor_year is NULL, we cannot compute DOB, so exclude these patients.
    DATE_SUB(DATE(anchor_year, 1, 1), INTERVAL anchor_age YEAR) AS dob
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE anchor_year IS NOT NULL
),

-- Step 2: Get ICU stays for male patients aged 45-55
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    TIMESTAMP_DIFF(i.intime, p.dob, YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN patient_dob p ON i.subject_id = p.subject_id
  WHERE
    -- Gender is in patients table, but we don't have it here. We need to join with patients to get gender.
    -- Let's join with patients to get gender.
    -- We'll do the join in the next CTE to avoid duplication.
    -- Instead, we'll do the gender filter in the next CTE.
    TIMESTAMP_DIFF(i.intime, p.dob, YEAR) BETWEEN 45 AND 55
),

-- Step 3: Join with patients to get gender and filter for male
icu_stays_male AS (
  SELECT
    i.*,
    pt.gender
  FROM icu_stays i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt ON i.subject_id = pt.subject_id
  WHERE pt.gender = 'M'
),

-- Step 4: Identify ARF stays (using diagnoses_icd)
arf_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.age_at_admission,
    s.gender
  FROM icu_stays_male s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON s.subject_id = d.subject_id AND s.hadm_id = d.hadm_id
  WHERE d.icd_code IN ('J98.9', 'J96.9') AND d.icd_version = 10
),

-- Step 5: Get vital signs for HR, MAP, RR from chartevents in the first 48 hours
-- We'll define the itemids for each parameter. We'll use a subquery to get the itemids from d_items.
vitals AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valueuom,
    ce.valuenum,
    CASE
      WHEN di.label LIKE '%Heart Rate%' THEN 'HR'
      WHEN di.label LIKE '%MAP%' OR di.label LIKE '%Mean Arterial Pressure%' THEN 'MAP'
      WHEN di.label LIKE '%Respiratory Rate%' THEN 'RR'
    END AS parameter
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    ce.stay_id IS NOT NULL
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND di.category = 'Vital Signs'
    AND ce.charttime BETWEEN (SELECT MIN(intime) FROM icu_stays_male) AND (SELECT MAX(outtime) FROM icu_stays_male)
    -- We'll filter by time relative to ICU stay later in the CTE
),

-- We'll create a CTE for each parameter separately to make it easier, but we can do it in one.
-- Instead, we'll pivot the vitals to have one row per stay_id, charttime, and parameter.
vitals_pivoted AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    MAX(CASE WHEN parameter = 'HR' THEN valuenum END) AS hr,
    MAX(CASE WHEN parameter = 'MAP' THEN valuenum END) AS map,
    MAX(CASE WHEN parameter = 'RR' THEN valuenum END) AS rr
  FROM vitals
  GROUP BY subject_id, hadm_id, stay_id, charttime
),

-- Step 6: For each ICU stay, get the first 6 hours of data for baseline
baseline AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    AVG(v.hr) AS baseline_hr,
    AVG(v.map) AS baseline_map,
    AVG(v.rr) AS baseline_rr
  FROM vitals_pivoted v
  INNER JOIN icu_stays_male s
    ON v.subject_id = s.subject_id AND v.hadm_id = s.hadm_id AND v.stay_id = s.stay_id
  WHERE
    v.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 6 HOUR)
  GROUP BY v.subject_id, v.hadm_id, v.stay_id
),

-- Step 7: For each hour in the first 48 hours, get the last value for each parameter
-- We'll generate a time series for each stay_id for each hour in the first 48 hours.
-- Then, for each hour, get the last vital sign value in that hour.
hourly_vitals AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    -- Generate a series of hours from 0 to 47
    GENERATE_TIMESTAMP_ARRAY(s.intime, TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR), INTERVAL 1 HOUR) AS hour_start,
    -- We'll use a lateral join to unnest the array
  FROM icu_stays_male s
  -- We'll use a lateral join to unnest the array of hours
  CROSS JOIN UNNEST(GENERATE_TIMESTAMP_ARRAY(s.intime, TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR), INTERVAL 1 HOUR)) AS hour_start
  -- Then, for each hour, get the last vital sign value in [hour_start, hour_start + 1 HOUR)
  LEFT JOIN vitals_pivoted v
    ON s.subject_id = v.subject_id
    AND s.hadm_id = v.hadm_id
    AND s.stay_id = v.stay_id
    AND v.charttime >= hour_start
    AND v.charttime < TIMESTAMP_ADD(hour_start, INTERVAL 1 HOUR)
  -- For each hour, we want the last value in the hour. We can use LAST_VALUE with IGNORE NULLS, but we'll do it per hour.
  -- Instead, we can use a subquery to get the last value per hour per parameter.
  -- We'll do this in a separate CTE to avoid complexity.
),

-- Given the complexity and potential performance issues, we might need to break down further.
-- We'll create a CTE to get the last value per hour per parameter per stay.
hourly_vitals_last AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    TIMESTAMP_TRUNC(v.charttime, HOUR) AS hour_start,
    v.hr,
    v.map,
    v.rr
  FROM vitals_pivoted v
  INNER JOIN icu_stays_male s
    ON v.subject_id = s.subject_id AND v.hadm_id = s.hadm_id AND v.stay_id = s.stay_id
  WHERE
    v.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY v.subject_id, v.hadm_id, v.stay_id, TIMESTAMP_TRUNC(v.charttime, HOUR), 
                 CASE WHEN v.hr IS NOT NULL THEN 'HR' 
                      WHEN v.map IS NOT NULL THEN 'MAP'
                      WHEN v.rr IS NOT NULL THEN 'RR'
                 END 
    ORDER BY v.charttime DESC
  ) = 1
  -- This will get the last non-null value for each parameter in each hour. But note: we might have multiple parameters in one hour.
  -- We want one row per hour per stay, with the last value for each parameter that has data in that hour.
  -- We can pivot again.
),

-- Then, we can aggregate by hour to have one row per hour per stay with the last values for each parameter.
hourly_vitals_agg AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    hour_start,
    MAX(hr) AS hr,  -- Since we have one value per parameter per hour, MAX is the same as the value
    MAX(map) AS map,
    MAX(rr) AS rr
  FROM hourly_vitals_last
  GROUP BY subject_id, hadm_id, stay_id, hour_start
),

-- Step 8: Compute hourly changes from baseline
hourly_changes AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.stay_id,
    h.hour_start,
    -- For each parameter, if baseline exists and current value exists, compute absolute change
    ABS(h.hr - b.baseline_hr) AS hr_change,
    ABS(h.map - b.baseline_map) AS map_change,
    ABS(h.rr - b.baseline_rr) AS rr_change
  FROM hourly_vitals_agg h
  INNER JOIN baseline b
    ON h.subject_id = b.subject_id AND h.hadm_id = b.hadm_id AND h.stay_id = b.stay_id
  -- Only consider hours where at least one parameter has data
  WHERE
    (h.hr IS NOT NULL AND b.baseline_hr IS NOT NULL) OR
    (h.map IS NOT NULL AND b.baseline_map IS NOT NULL) OR
    (h.rr IS NOT NULL AND b.baseline_rr IS NOT NULL)
),

-- Then, for each hour, take the max change across parameters
hourly_max_change AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    hour_start,
    GREATEST(
      COALESCE(hr_change, 0),
      COALESCE(map_change, 0),
      COALESCE(rr_change, 0)
    ) AS max_change
  FROM hourly_changes
),

-- Step 9: Compute instability score per stay (max over hours of max_change)
instability_score AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    MAX(max_change) AS instability_score
  FROM hourly_max_change
  GROUP BY subject_id, hadm_id, stay_id
),

-- Step 10: For the entire cohort (male 45-55 ICU), compute the 95th percentile of instability_score
-- Note: We must include all ICU stays in the cohort, even if instability_score is NULL.
all_scores AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    i.instability_score
  FROM icu_stays_male s
  LEFT JOIN instability_score i
    ON s.subject_id = i.subject_id AND s.hadm_id = i.hadm_id AND s.stay_id = i.stay_id
),

-- Compute the 95th percentile
percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_instability
  FROM all_scores
  WHERE instability_score IS NOT NULL
),

-- Step 11: For the ARF cohort, define top quartile
arf_with_score AS (
  SELECT
    a.*,
    i.instability_score
  FROM arf_stays a
  LEFT JOIN instability_score i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id AND a.stay_id = i.stay_id
),

-- Compute the 75th percentile for ARF cohort
arf_percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_instability
  FROM arf_with_score
  WHERE instability_score IS NOT NULL
),

-- Top quartile ARF: instability_score >= p75_instability
top_quartile_arf AS (
  SELECT
    a.*,
    a.instability_score
  FROM arf_with_score a
  CROSS JOIN arf_percentiles p
  WHERE a.instability_score >= p.p75_instability
),

-- Step 12: Control group: male, 45-55, ICU, without ARF
control_group AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.age_at_admission,
    s.gender,
    i.instability_score
  FROM icu_stays_male s
  LEFT JOIN instability_score i
    ON s.subject_id = i.subject_id AND s.hadm_id = i.hadm_id AND s.stay_id = i.stay_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM arf_stays a
    WHERE a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  )
),

-- Step 13: Compute outcomes for top_quartile_arf and control_group
-- We need to compute:
--   Hypotension (MAP < 65) in first 48 hours: binary
--   Tachycardia (HR > 100) in first 48 hours: binary
--   ICU LOS (outtime - intime) in hours
--   Mortality (from admissions.hospital_expire_flag)

-- First, get the outcomes from chartevents for hypotension and tachycardia in the first 48 hours.
-- We'll create a CTE for each event.

-- Hypotension: MAP < 65 in first 48 hours
hypotension AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    BOOL_OR(v.map < 65) AS hypotension_occurred
  FROM vitals_pivoted v
  INNER JOIN icu_stays_male s
    ON v.subject_id = s.subject_id AND v.hadm_id = s.hadm_id AND v.stay_id = s.stay_id
  WHERE
    v.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND v.map IS NOT NULL
  GROUP BY v.subject_id, v.hadm_id, v.stay_id
),

-- Tachycardia: HR > 100 in first 48 hours
tachycardia AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    BOOL_OR(v.hr > 100) AS tachycardia_occurred
  FROM vitals_pivoted v
  INNER JOIN icu_stays_male s
    ON v.subject_id = s.subject_id AND v.hadm_id = s.hadm_id AND v.stay_id = s.stay_id
  WHERE
    v.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND v.hr IS NOT NULL
  GROUP BY v.subject_id, v.hadm_id, v.stay_id
),

-- ICU LOS in hours
los AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    TIMESTAMP_DIFF(outtime, intime, HOUR) AS los_hours
  FROM icu_stays_male
),

-- Mortality from admissions
mortality AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag AS mortality
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.gender = 'M' -- though we already have male in icu_stays_male, but to be safe
),

-- Now, combine outcomes for top_quartile_arf and control_group
outcomes_by_group AS (
  -- For top_quartile_arf
  SELECT
    'top_quartile_ARF' AS group_type,
    t.subject_id,
    t.hadm_id,
    t.stay_id,
    COALESCE(h.hypotension_occurred, FALSE) AS hypotension_occurrence,
    COALESCE(ta.tachycardia_occurred, FALSE) AS tachycardia_occurrence,
    l.los_hours,
    m.mortality
  FROM top_quartile_arf t
  LEFT JOIN hypotension h
    ON t.subject_id = h.subject_id AND t.hadm_id = h.hadm_id AND t.stay_id = h.stay_id
  LEFT JOIN tachycardia ta
    ON t.subject_id = ta.subject_id AND t.hadm_id = ta.hadm_id AND t.stay_id = ta.stay_id
  LEFT JOIN los l
    ON t.subject_id = l.subject_id AND t.hadm_id = l.hadm_id AND t.stay_id = l.stay_id
  LEFT JOIN mortality m
    ON t.subject_id = m.subject_id AND t.hadm_id = m.hadm_id

  UNION ALL

  -- For control_group
  SELECT
    'control' AS group_type,
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COALESCE(h.hypotension_occurred, FALSE) AS hypotension_occurrence,
    COALESCE(ta.tachycardia_occurred, FALSE) AS tachycardia_occurrence,
    l.los_hours,
    m.mortality
  FROM control_group c
  LEFT JOIN hypotension h
    ON c.subject_id = h.subject_id AND c.hadm_id = h.hadm_id AND c.stay_id = h.stay_id
  LEFT JOIN tachycardia ta
    ON c.subject_id = ta.subject_id AND c.hadm_id = ta.hadm_id AND c.stay_id = ta.stay_id
  LEFT JOIN los l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id AND c.stay_id = l.stay_id
  LEFT JOIN mortality m
    ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
),

-- Step 14: Aggregate outcomes by group_type
aggregated_outcomes AS (
  SELECT
    group_type,
    AVG(CAST(hypotension_occurrence AS FLOAT64)) AS hypotension_rate,
    AVG(CAST(tachycardia_occurrence AS FLOAT64)) AS tachycardia_rate,
    AVG(los_hours) AS avg_los_hours,
    AVG(CAST(mortality AS FLOAT64)) AS mortality_rate
  FROM outcomes_by_group
  GROUP BY group_type
),

-- Step 15: Combine with the 95th percentile
final_output AS (
  SELECT
    '95th_percentile_instability_score' AS metric,
    p95_instability AS value,
    NULL AS group_type
  FROM percentiles

  UNION ALL

  SELECT
    'hypotension_occurrence' AS metric,
    hypotension_rate AS value,
    group_type
  FROM aggregated_outcomes

  UNION ALL

  SELECT
    'tachycardia_occurrence' AS metric,
    tachycardia_rate AS value,
    group_type
  FROM aggregated_outcomes

  UNION ALL

  SELECT
    'avg_los_hours' AS metric,
    avg_los_hours AS value,
    group_type
  FROM aggregated_outcomes

  UNION ALL

  SELECT
    'mortality_rate' AS metric,
    mortality_rate AS value,
    group_type
  FROM aggregated_outcomes
)

SELECT * FROM final_output
ORDER BY metric, group_type;