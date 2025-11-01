WITH vital_sign_items AS (
  SELECT itemid, label, lownormalvalue, highnormalvalue
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE linksto = 'chartevents'
    AND category IN ('Vital Signs', 'Monitoring')
    AND lownormalvalue IS NOT NULL
    AND highnormalvalue IS NOT NULL
    AND label IN (
      'Heart Rate',
      'Mean Arterial Pressure',
      'Respiratory Rate',
      'SpO2',
      'Temperature',
      'Systolic BP',
      'Diastolic BP'
    )
),

-- Identify ischemic stroke patients (first ICU stay per admission)
stroke_patients AS (
  SELECT DISTINCT
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON i.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND (
      LOWER(dd.long_title) LIKE '%ischemic stroke%'
      OR LOWER(dd.long_title) LIKE '%cerebral infarction%'
      OR d.icd_code IN ('433.01', '433.11', '433.21', '433.31', '433.81', '433.91', '434.01', '434.11', '434.91', '436')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
),

-- Get first ICU stay per admission (in case of multiple)
first_icu_stay AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM stroke_patients
),
stroke_first AS (
  SELECT * FROM first_icu_stay WHERE rn = 1
),

-- Compute abnormal events in first 48 hours for stroke patients
abnormal_events_stroke AS (
  SELECT
    s.stay_id,
    COUNT(*) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN vital_sign_items v ON c.itemid = v.itemid
  JOIN stroke_first s ON c.stay_id = s.stay_id
  WHERE c.charttime >= s.intime
    AND c.charttime <= s.intime + INTERVAL '48 hour'
    AND c.valuenum IS NOT NULL
    AND (c.valuenum < v.lownormalvalue OR c.valuenum > v.highnormalvalue)
  GROUP BY s.stay_id
),

-- Compute instability score for all eligible ICU patients (non-stroke)
all_icu_patients AS (
  SELECT DISTINCT
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    CASE WHEN s.stay_id IS NOT NULL THEN 1 ELSE 0 END AS is_stroke
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  LEFT JOIN stroke_first s ON i.stay_id = s.stay_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
),

-- Compute abnormal events for all ICU patients
abnormal_events_all AS (
  SELECT
    a.stay_id,
    a.is_stroke,
    COUNT(*) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN vital_sign_items v ON c.itemid = v.itemid
  JOIN all_icu_patients a ON c.stay_id = a.stay_id
  WHERE c.charttime >= a.intime
    AND c.charttime <= a.intime + INTERVAL '48 hour'
    AND c.valuenum IS NOT NULL
    AND (c.valuenum < v.lownormalvalue OR c.valuenum > v.highnormalvalue)
  GROUP BY a.stay_id, a.is_stroke
),

-- Compute 95th percentile of instability score among stroke patients
top_percentile_threshold AS (
  SELECT PERCENTILE_CONT(instability_score, 0.95) AS p95
  FROM abnormal_events_stroke
),

-- Filter to top 5% (instability score >= 95th percentile) for both groups
top_percentile_patients AS (
  SELECT
    a.stay_id,
    a.is_stroke,
    a.instability_score,
    a.los,
    a.hospital_expire_flag
  FROM abnormal_events_all a
  CROSS JOIN top_percentile_threshold t
  WHERE a.instability_score >= t.p95
)

-- Final comparison: stroke vs non-stroke in top 5%
SELECT
  SUM(is_stroke) AS stroke_n,
  SUM(1 - is_stroke) AS non_stroke_n,
  AVG(instability_score) AS mean_instability_score,
  AVG(instability_score) AS mean_abnormal_episodes,
  AVG(los * 24) AS mean_icu_los_hours,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM top_percentile_patients
GROUP BY is_stroke
ORDER BY is_stroke DESC;