WITH
-- Step 1: Identify eligible patients (male, aged 63-73)
eligible_patients AS (
  SELECT
    subject_id,
    anchor_age,
    gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 63 AND 73
),
-- Step 2: Find post-op admissions (with at least one procedure) and get the first admission per patient
postop_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients ep
    ON a.subject_id = ep.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON a.hadm_id = proc.hadm_id
  WHERE
    a.admittime IS NOT NULL
),
first_admission_per_patient AS (
  SELECT
    subject_id,
    MIN(admittime) AS first_admittime
  FROM postop_admissions
  GROUP BY subject_id
),
first_admission AS (
  SELECT
    p.*
  FROM postop_admissions p
  JOIN first_admission_per_patient f
    ON p.subject_id = f.subject_id AND p.admittime = f.first_admittime
),
-- Step 3: Get the first ICU stay for each patient (using the first admission)
icu_stays_first AS (
  SELECT
    i.*
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN first_admission f
    ON i.subject_id = f.subject_id AND i.hadm_id = f.hadm_id
  WHERE
    i.intime IS NOT NULL
    AND i.outtime IS NOT NULL
),
-- Step 4: Compute instability score (count of distinct abnormal vital signs in first 24 hours of ICU stay)
-- Define vital sign itemids and thresholds
first_24h_chartevents AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.itemid,
    c.valuenum,
    c.charttime,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN icu_stays_first i
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  WHERE
    c.charttime BETWEEN i.intime AND i.intime + INTERVAL 24 HOUR
    AND c.valuenum IS NOT NULL
),
abnormal_events AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    CASE
      WHEN itemid IN (211, 220045) AND valuenum > 100 THEN 'hr'
      WHEN itemid IN (442, 456, 52, 6702) AND valuenum < 90 THEN 'sbp'
      WHEN itemid IN (220210, 618, 224689) AND valuenum > 20 THEN 'rr'
      WHEN itemid IN (223761, 678, 223835) AND (valuenum > 38.5 OR valuenum < 36) THEN 'temp'
      WHEN itemid IN (220250, 220050, 220179) AND valuenum < 90 THEN 'spo2'
    END AS abnormal_type
  FROM first_24h_chartevents
  WHERE abnormal_type IS NOT NULL
),
instability_score_cte AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNT(DISTINCT abnormal_type) AS instability_score
  FROM abnormal_events
  GROUP BY subject_id, hadm_id, stay_id
),
-- Step 5: Compute episodes in the entire ICU stay (fever, SpO2<90%, RR>20)
all_chartevents AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.itemid,
    c.valuenum,
    c.charttime,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN icu_stays_first i
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  WHERE
    c.charttime BETWEEN i.intime AND i.outtime
    AND c.valuenum IS NOT NULL
),
fever_episodes AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNT(*) AS fever_count
  FROM all_chartevents
  WHERE
    itemid IN (223761, 678, 223835)
    AND valuenum > 38.5
  GROUP BY subject_id, hadm_id, stay_id
),
spo2_episodes AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNT(*) AS spo2_count
  FROM all_chartevents
  WHERE
    itemid IN (220250, 220050, 220179)
    AND valuenum < 90
  GROUP BY subject_id, hadm_id, stay_id
),
rr_episodes AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNT(*) AS rr_count
  FROM all_chartevents
  WHERE
    itemid IN (220210, 618, 224689)
    AND valuenum > 20
  GROUP BY subject_id, hadm_id, stay_id
),
-- Step 6: Combine all metrics for each ICU stay
patients_with_metrics AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS los_hours,
    a.hospital_expire_flag AS died_in_hospital,
    COALESCE(is.instability_score, 0) AS instability_score,
    COALESCE(f.fever_count, 0) AS fever_episodes,
    COALESCE(s.spo2_count, 0) AS spo2_episodes,
    COALESCE(r.rr_count, 0) AS rr_episodes
  FROM icu_stays_first i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  LEFT JOIN instability_score_cte is
    ON i.subject_id = is.subject_id AND i.hadm_id = is.hadm_id AND i.stay_id = is.stay_id
  LEFT JOIN fever_episodes f
    ON i.subject_id = f.subject_id AND i.hadm_id = f.hadm_id AND i.stay_id = f.stay_id
  LEFT JOIN spo2_episodes s
    ON i.subject_id = s.subject_id AND i.hadm_id = s.hadm_id AND i.stay_id = s.stay_id
  LEFT JOIN rr_episodes r
    ON i.subject_id = r.subject_id AND i.hadm_id = r.hadm_id AND i.stay_id = r.stay_id
),
-- Step 7: Compute the top quartile cutoff for instability_score
instability_cutoff AS (
  SELECT
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY instability_score) AS cutoff
  FROM patients_with_metrics
),
-- Step 8: Assign group (target or comparison) based on instability_score
patients_with_group AS (
  SELECT
    *,
    CASE
      WHEN instability_score >= (SELECT cutoff FROM instability_cutoff) THEN 'target'
      ELSE 'comparison'
    END AS group
  FROM patients_with_metrics
),
-- Step 9: For the target group, compute the 95th percentile of instability_score
target_95th_percentile AS (
  SELECT
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY instability_score) AS instability_95th_percentile
  FROM patients_with_group
  WHERE group = 'target'
),
-- Step 10: Aggregate by group
target_agg AS (
  SELECT
    'target' AS group,
    (SELECT instability_95th_percentile FROM target_95th_percentile) AS instability_95th_percentile,
    AVG(fever_episodes) AS avg_fever_episodes,
    AVG(spo2_episodes) AS avg_spo2_episodes,
    AVG(rr_episodes) AS avg_rr_episodes,
    AVG(los_hours) AS avg_los,
    AVG(CAST(died_in_hospital AS FLOAT64)) AS mortality_rate
  FROM patients_with_group
  WHERE group = 'target'
),
comparison_agg AS (
  SELECT
    'comparison' AS group,
    NULL AS instability_95th_percentile,
    AVG(fever_episodes) AS avg_fever_episodes,
    AVG(spo2_episodes) AS avg_spo2_episodes,
    AVG(rr_episodes) AS avg_rr_episodes,
    AVG(los_hours) AS avg_los,
    AVG(CAST(died_in_hospital AS FLOAT64)) AS mortality_rate
  FROM patients_with_group
  WHERE group = 'comparison'
)
-- Step 11: Combine results
SELECT * FROM target_agg
UNION ALL
SELECT * FROM comparison_agg;