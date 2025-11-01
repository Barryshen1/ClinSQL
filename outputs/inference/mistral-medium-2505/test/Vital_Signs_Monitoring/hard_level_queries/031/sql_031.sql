WITH
-- Define post-op patients (using procedure codes or surgical admissions)
post_op_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc ON a.subject_id = proc.subject_id AND a.hadm_id = proc.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND proc.icd_code LIKE '0%'  -- Surgical procedure codes typically start with 0
),

-- Get ICU stays for post-op patients
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    post_op_patients p ON i.subject_id = p.subject_id AND i.hadm_id = p.hadm_id
),

-- Calculate instability score components
vital_signs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    -- Temperature (itemid 223761 for Celsius)
    MAX(CASE WHEN c.itemid = 223761 AND c.valuenum > 38.5 THEN 1 ELSE 0 END) AS has_fever,
    -- SpO2 (itemid 220277)
    MAX(CASE WHEN c.itemid = 220277 AND c.valuenum < 90 THEN 1 ELSE 0 END) AS has_low_spo2,
    -- Respiratory Rate (itemid 220210)
    MAX(CASE WHEN c.itemid = 220210 AND c.valuenum > 20 THEN 1 ELSE 0 END) AS has_high_rr
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays i ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  WHERE
    c.itemid IN (223761, 220277, 220210)  -- Temperature, SpO2, Respiratory Rate
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id
),

-- Calculate instability score (simple sum of abnormal vital signs)
instability_scores AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    (v.has_fever + v.has_low_spo2 + v.has_high_rr) AS instability_score,
    i.icu_los_hours,
    p.hospital_expire_flag
  FROM
    vital_signs v
  JOIN
    icu_stays i ON v.subject_id = i.subject_id AND v.hadm_id = i.hadm_id AND v.stay_id = i.stay_id
  JOIN
    post_op_patients p ON v.subject_id = p.subject_id AND v.hadm_id = p.hadm_id
),

-- Identify top quartile of instability
quartiles AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.75) OVER() AS q75,
    PERCENTILE_CONT(instability_score, 0.95) OVER() AS p95
  FROM
    instability_scores
  LIMIT 1
),

-- Get the 95th percentile instability score
p95_score AS (
  SELECT
    MAX(p95) AS instability_score_95th_percentile
  FROM
    quartiles
),

-- Compare top quartile to others
comparison AS (
  SELECT
    s.*,
    CASE WHEN s.instability_score >= q.q75 THEN 'Top Quartile' ELSE 'Other' END AS instability_group
  FROM
    instability_scores s
  CROSS JOIN
    quartiles q
),

-- Calculate median ICU LOS by group
icu_los_medians AS (
  SELECT
    instability_group,
    PERCENTILE_CONT(icu_los_hours, 0.5) OVER(PARTITION BY instability_group) AS median_icu_los
  FROM
    comparison
  GROUP BY
    instability_group, icu_los_hours
)

-- Final results wrapped in a parent query
SELECT * FROM (
  SELECT
    '95th Percentile Instability Score' AS metric,
    p.instability_score_95th_percentile AS value
  FROM
    p95_score p

  UNION ALL

  SELECT
    'Fever (>38.5°C) in Top Quartile' AS metric,
    SUM(CASE WHEN c.instability_group = 'Top Quartile' AND v.has_fever = 1 THEN 1 ELSE 0 END) AS value
  FROM
    comparison c
    JOIN vital_signs v ON c.subject_id = v.subject_id AND c.hadm_id = v.hadm_id AND c.stay_id = v.stay_id

  UNION ALL

  SELECT
    'Fever (>38.5°C) in Other Patients' AS metric,
    SUM(CASE WHEN c.instability_group = 'Other' AND v.has_fever = 1 THEN 1 ELSE 0 END) AS value
  FROM
    comparison c
    JOIN vital_signs v ON c.subject_id = v.subject_id AND c.hadm_id = v.hadm_id AND c.stay_id = v.stay_id

  UNION ALL

  SELECT
    'SpO2 < 90% in Top Quartile' AS metric,
    SUM(CASE WHEN c.instability_group = 'Top Quartile' AND v.has_low_spo2 = 1 THEN 1 ELSE 0 END) AS value
  FROM
    comparison c
    JOIN vital_signs v ON c.subject_id = v.subject_id AND c.hadm_id = v.hadm_id AND c.stay_id = v.stay_id

  UNION ALL

  SELECT
    'SpO2 < 90% in Other Patients' AS metric,
    SUM(CASE WHEN c.instability_group = 'Other' AND v.has_low_spo2 = 1 THEN 1 ELSE 0 END) AS value
  FROM
    comparison c
    JOIN vital_signs v ON c.subject_id = v.subject_id AND c.hadm_id = v.hadm_id AND c.stay_id = v.stay_id

  UNION ALL

  SELECT
    'RR > 20 in Top Quartile' AS metric,
    SUM(CASE WHEN c.instability_group = 'Top Quartile' AND v.has_high_rr = 1 THEN 1 ELSE 0 END) AS value
  FROM
    comparison c
    JOIN vital_signs v ON c.subject_id = v.subject_id AND c.hadm_id = v.hadm_id AND c.stay_id = v.stay_id

  UNION ALL

  SELECT
    'RR > 20 in Other Patients' AS metric,
    SUM(CASE WHEN c.instability_group = 'Other' AND v.has_high_rr = 1 THEN 1 ELSE 0 END) AS value
  FROM
    comparison c
    JOIN vital_signs v ON c.subject_id = v.subject_id AND c.hadm_id = v.hadm_id AND c.stay_id = v.stay_id

  UNION ALL

  SELECT
    'Median ICU LOS (hours) in Top Quartile' AS metric,
    MAX(CASE WHEN instability_group = 'Top Quartile' THEN median_icu_los ELSE NULL END) AS value
  FROM
    icu_los_medians

  UNION ALL

  SELECT
    'Median ICU LOS (hours) in Other Patients' AS metric,
    MAX(CASE WHEN instability_group = 'Other' THEN median_icu_los ELSE NULL END) AS value
  FROM
    icu_los_medians

  UNION ALL

  SELECT
    'In-hospital Mortality in Top Quartile' AS metric,
    SUM(CASE WHEN c.instability_group = 'Top Quartile' AND c.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS value
  FROM
    comparison c

  UNION ALL

  SELECT
    'In-hospital Mortality in Other Patients' AS metric,
    SUM(CASE WHEN c.instability_group = 'Other' AND c.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS value
  FROM
    comparison c
)
ORDER BY metric;