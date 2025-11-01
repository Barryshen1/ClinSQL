WITH
-- Get male patients aged 55-65
patient_demo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 55 AND 65
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    i.hadm_id = a.hadm_id
  JOIN
    patient_demo p
  ON
    i.subject_id = p.subject_id
),

-- Identify HFNC patients (within 24 hours of ICU admission)
hfnc_patients AS (
  SELECT DISTINCT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    (di.label LIKE '%HFNC%' OR di.label LIKE '%High Flow Nasal Cannula%')
    AND TIMESTAMP_DIFF(ce.charttime, (
      SELECT icu_intime
      FROM icu_stays
      WHERE subject_id = ce.subject_id AND hadm_id = ce.hadm_id AND stay_id = ce.stay_id
    ), HOUR) <= 24
),

-- Get control patients (same age/gender but no HFNC)
control_patients AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id
  FROM
    icu_stays i
  LEFT JOIN
    hfnc_patients h
  ON
    i.subject_id = h.subject_id AND i.hadm_id = h.hadm_id AND i.stay_id = h.stay_id
  WHERE
    h.subject_id IS NULL
),

-- Combine HFNC and control groups with labels
study_groups AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    'HFNC' AS group_type
  FROM
    hfnc_patients
  UNION ALL
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    'Control' AS group_type
  FROM
    control_patients
),

-- Calculate instability score components
vital_signs AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    -- Heart rate
    MAX(CASE WHEN di.label LIKE '%Heart Rate%' THEN ce.valuenum ELSE NULL END) AS heart_rate,
    -- Systolic BP
    MAX(CASE WHEN di.label LIKE '%Systolic%' AND di.label LIKE '%BP%' THEN ce.valuenum ELSE NULL END) AS systolic_bp,
    -- Diastolic BP
    MAX(CASE WHEN di.label LIKE '%Diastolic%' AND di.label LIKE '%BP%' THEN ce.valuenum ELSE NULL END) AS diastolic_bp,
    -- Mean BP
    MAX(CASE WHEN di.label LIKE '%Mean%' AND di.label LIKE '%BP%' THEN ce.valuenum ELSE NULL END) AS mean_bp,
    -- Respiratory rate
    MAX(CASE WHEN di.label LIKE '%Respiratory Rate%' THEN ce.valuenum ELSE NULL END) AS respiratory_rate,
    -- SpO2
    MAX(CASE WHEN di.label LIKE '%SpO2%' THEN ce.valuenum ELSE NULL END) AS spo2
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    ce.charttime BETWEEN (
      SELECT icu_intime
      FROM icu_stays
      WHERE subject_id = ce.subject_id AND hadm_id = ce.hadm_id AND stay_id = ce.stay_id
    ) AND (
      SELECT icu_outtime
      FROM icu_stays
      WHERE subject_id = ce.subject_id AND hadm_id = ce.hadm_id AND stay_id = ce.stay_id
    )
  GROUP BY
    ce.subject_id, ce.hadm_id, ce.stay_id, ce.charttime
),

-- Calculate instability score (simplified example - would need clinical validation)
instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(
      CASE
        WHEN heart_rate > 100 THEN 1 ELSE 0 END +
        CASE WHEN systolic_bp < 90 THEN 1 ELSE 0 END +
        CASE WHEN respiratory_rate > 20 THEN 1 ELSE 0 END +
        CASE WHEN spo2 < 90 THEN 1 ELSE 0 END
    ) AS instability_score
  FROM
    vital_signs
  GROUP BY
    subject_id, hadm_id, stay_id
),

-- Calculate tachycardia burden (percentage of time with HR > 100)
tachycardia_burden AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    SUM(CASE WHEN heart_rate > 100 THEN 1 ELSE 0 END) /
    COUNT(*) AS tachycardia_burden
  FROM
    vital_signs
  GROUP BY
    subject_id, hadm_id, stay_id
),

-- Calculate hypotension burden (percentage of time with SBP < 90)
hypotension_burden AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    SUM(CASE WHEN systolic_bp < 90 THEN 1 ELSE 0 END) /
    COUNT(*) AS hypotension_burden
  FROM
    vital_signs
  GROUP BY
    subject_id, hadm_id, stay_id
),

-- Combine all metrics
final_metrics AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.group_type,
    i.instability_score,
    t.tachycardia_burden,
    h.hypotension_burden,
    icu.icu_los_hours,
    icu.hospital_expire_flag
  FROM
    study_groups s
  JOIN
    instability_scores i
  ON
    s.subject_id = i.subject_id AND s.hadm_id = i.hadm_id AND s.stay_id = i.stay_id
  JOIN
    tachycardia_burden t
  ON
    s.subject_id = t.subject_id AND s.hadm_id = t.hadm_id AND s.stay_id = t.stay_id
  JOIN
    hypotension_burden h
  ON
    s.subject_id = h.subject_id AND s.hadm_id = h.hadm_id AND s.stay_id = h.stay_id
  JOIN
    icu_stays icu
  ON
    s.subject_id = icu.subject_id AND s.hadm_id = icu.hadm_id AND s.stay_id = icu.stay_id
)

-- Final results with percentiles
SELECT
  group_type,
  COUNT(*) AS patient_count,
  -- Instability score metrics
  APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS median_instability_score,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(0)] AS p25_instability_score,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(2)] AS p75_instability_score,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(94)] AS p95_instability_score,
  -- Tachycardia burden
  AVG(tachycardia_burden) AS avg_tachycardia_burden,
  -- Hypotension burden
  AVG(hypotension_burden) AS avg_hypotension_burden,
  -- ICU LOS
  AVG(icu_los_hours) AS avg_icu_los_hours,
  -- Mortality
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM
  final_metrics
GROUP BY
  group_type
ORDER BY
  group_type;