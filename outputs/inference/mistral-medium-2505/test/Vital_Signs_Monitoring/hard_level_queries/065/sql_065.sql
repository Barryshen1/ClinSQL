WITH
-- Get male patients aged 70-80
male_patients_70_80 AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 70 AND 80
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) AS icu_los_hours,
    s.first_careunit,
    s.last_careunit
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    male_patients_70_80 p ON s.subject_id = p.subject_id
),

-- Identify RRT procedures (using common procedure codes for renal replacement therapy)
rrt_procedures AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE
    icd_code IN (
      '39.95',  -- Hemodialysis
      '54.98',  -- Continuous renal replacement therapy
      '39.94',  -- Peritoneal dialysis
      '39.93'   -- Hemofiltration
    )
    AND icd_version = '10'
),

-- Get patients with RRT
rrt_patients AS (
  SELECT DISTINCT
    i.subject_id,
    i.hadm_id,
    i.stay_id
  FROM
    icu_stays i
  JOIN
    rrt_procedures r ON i.subject_id = r.subject_id AND i.hadm_id = r.hadm_id
),

-- Get vital signs data for first 48 hours of ICU stay
vital_signs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum,
    TIMESTAMP_DIFF(c.charttime, i.intime, HOUR) AS hours_since_admission,
    d.label AS item_label
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays i ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE
    TIMESTAMP_DIFF(c.charttime, i.intime, HOUR) BETWEEN 0 AND 48
    AND c.itemid IN (220050, 220045, 220046, 220048, 220049)
),

-- Calculate composite vital instability score (simplified example)
vital_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    -- Count of hypotension episodes (MAP < 65)
    SUM(CASE WHEN itemid = 220050 AND valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_episodes,
    -- Count of tachycardia episodes (HR > 100)
    SUM(CASE WHEN itemid = 220045 AND valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_episodes,
    -- Other vital sign abnormalities could be added here
    -- Composite score (example: sum of abnormal episodes)
    SUM(CASE WHEN (itemid = 220050 AND valuenum < 65) OR (itemid = 220045 AND valuenum > 100) THEN 1 ELSE 0 END) AS composite_score
  FROM
    vital_signs
  GROUP BY
    subject_id, hadm_id, stay_id
),

-- Get 90th percentile of composite score for RRT patients
score_percentiles AS (
  SELECT
    PERCENTILE_CONT(composite_score, 0.9) OVER() AS p90_score
  FROM
    vital_scores vs
  JOIN
    rrt_patients r ON vs.subject_id = r.subject_id AND vs.hadm_id = r.hadm_id AND vs.stay_id = r.stay_id
),

-- Get top decile of RRT patients by composite score
top_decile_rrt AS (
  SELECT
    vs.subject_id,
    vs.hadm_id,
    vs.stay_id,
    vs.composite_score,
    vs.hypotension_episodes,
    vs.tachycardia_episodes,
    i.icu_los_hours,
    a.hospital_expire_flag AS mortality
  FROM
    vital_scores vs
  JOIN
    rrt_patients r ON vs.subject_id = r.subject_id AND vs.hadm_id = r.hadm_id AND vs.stay_id = r.stay_id
  JOIN
    icu_stays i ON vs.subject_id = i.subject_id AND vs.hadm_id = i.hadm_id AND vs.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON vs.subject_id = a.subject_id AND vs.hadm_id = a.hadm_id
  CROSS JOIN
    score_percentiles sp
  WHERE
    vs.composite_score >= sp.p90_score
),

-- Get comparison group (non-RRT patients)
non_rrt_patients AS (
  SELECT
    vs.subject_id,
    vs.hadm_id,
    vs.stay_id,
    vs.composite_score,
    vs.hypotension_episodes,
    vs.tachycardia_episodes,
    i.icu_los_hours,
    a.hospital_expire_flag AS mortality
  FROM
    vital_scores vs
  JOIN
    icu_stays i ON vs.subject_id = i.subject_id AND vs.hadm_id = i.hadm_id AND vs.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON vs.subject_id = a.subject_id AND vs.hadm_id = a.hadm_id
  WHERE
    vs.subject_id NOT IN (SELECT subject_id FROM rrt_patients)
    AND vs.hadm_id NOT IN (SELECT hadm_id FROM rrt_patients)
)

-- Final comparison
SELECT
  'Top decile RRT patients' AS group_name,
  COUNT(*) AS patient_count,
  AVG(hypotension_episodes) AS avg_hypotension_episodes,
  AVG(tachycardia_episodes) AS avg_tachycardia_episodes,
  AVG(icu_los_hours) AS avg_icu_los_hours,
  AVG(mortality) AS mortality_rate
FROM
  top_decile_rrt

UNION ALL

SELECT
  'Non-RRT patients' AS group_name,
  COUNT(*) AS patient_count,
  AVG(hypotension_episodes) AS avg_hypotension_episodes,
  AVG(tachycardia_episodes) AS avg_tachycardia_episodes,
  AVG(icu_los_hours) AS avg_icu_los_hours,
  AVG(mortality) AS mortality_rate
FROM
  non_rrt_patients;