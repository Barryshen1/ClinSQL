WITH
-- 1. Identify RRT itemids from d_items
rrt_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%dialysis%'
     OR LOWER(label) LIKE '%cvvh%'
     OR LOWER(label) LIKE '%cvvhd%'
     OR LOWER(label) LIKE '%cvvhdf%'
     OR LOWER(label) LIKE '%crrt%'
),

-- 2. Identify ICU stays for female patients aged 52-62
female_icu_patients AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 52 AND 62
),

-- 3. Identify patients who received RRT during ICU stay
rrt_stays AS (
  SELECT DISTINCT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los
  FROM female_icu_patients f
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.stay_id = pe.stay_id
    AND f.subject_id = pe.subject_id
    AND pe.starttime BETWEEN f.intime AND f.outtime
  JOIN rrt_items
    ON pe.itemid = rrt_items.itemid
),

-- 4. Get itemids for vital signs
vital_items AS (
  SELECT itemid, LOWER(label) AS label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('heart rate', 'hr', 'systolic blood pressure', 'sbp', 'respiratory rate', 'rr', 'spo2', 'oxygen saturation')
),

-- 5. Compute instability score for each patient in first 72h
instability_scores AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    r.stay_id,
    r.intime,
    r.outtime,
    r.los,
    -- Count abnormal events in first 72h
    SUM(
      CASE
        -- Heart Rate
        WHEN vi.label IN ('heart rate', 'hr') AND ce.valuenum IS NOT NULL AND (ce.valuenum < 40 OR ce.valuenum > 130) THEN 1
        -- Systolic BP
        WHEN vi.label IN ('systolic blood pressure', 'sbp') AND ce.valuenum IS NOT NULL AND ce.valuenum < 90 THEN 1
        -- Respiratory Rate
        WHEN vi.label IN ('respiratory rate', 'rr') AND ce.valuenum IS NOT NULL AND (ce.valuenum < 8 OR ce.valuenum > 30) THEN 1
        -- SpO2
        WHEN vi.label IN ('spo2', 'oxygen saturation') AND ce.valuenum IS NOT NULL AND ce.valuenum < 90 THEN 1
        ELSE 0
      END
    ) AS instability_score
  FROM rrt_stays r
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON r.stay_id = ce.stay_id
    AND ce.charttime BETWEEN r.intime AND DATETIME_ADD(r.intime, INTERVAL 72 HOUR)
  JOIN vital_items vi
    ON ce.itemid = vi.itemid
  GROUP BY r.subject_id, r.hadm_id, r.stay_id, r.intime, r.outtime, r.los
),

-- 6. Get mortality (hospital_expire_flag) for each stay
instability_scores_with_mortality AS (
  SELECT
    s.*,
    a.hospital_expire_flag
  FROM instability_scores s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
)

-- 7. Calculate percentile of score 65, and stats for top decile
SELECT
  -- Percentile of score 65
  ROUND(100 * (
    SELECT COUNT(*) FROM instability_scores_with_mortality WHERE instability_score < 65
  ) / (SELECT COUNT(*) FROM instability_scores_with_mortality), 1) AS percentile_of_65,

  -- Mean ICU LOS for top decile
  ROUND(AVG(los), 2) AS mean_icu_los_top_decile,

  -- Mortality rate for top decile
  ROUND(100 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 1) AS mortality_rate_top_decile

FROM (
  -- Top decile: patients with instability_score >= 90th percentile
  SELECT *
  FROM instability_scores_with_mortality
  WHERE instability_score >= (
    SELECT
      APPROX_QUANTILES(instability_score, 10)[OFFSET(9)]
    FROM instability_scores_with_mortality
  )
);