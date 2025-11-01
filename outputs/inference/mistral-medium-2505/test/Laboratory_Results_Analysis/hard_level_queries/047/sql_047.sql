WITH
-- Get male patients aged 71-81 with ARDS
ards_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND (d.icd_code = 'J80' OR d.icd_code = '518.82') -- ARDS codes
    AND a.hospital_expire_flag IS NOT NULL
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    ards_patients a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
),

-- Calculate instability score components from first 72 hours
instability_components AS (
  -- Heart rate (from chartevents)
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    'heart_rate' AS component,
    AVG(c.valuenum) AS avg_value,
    MAX(c.valuenum) AS max_value,
    MIN(c.valuenum) AS min_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays i
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
  WHERE
    di.label = 'Heart Rate'
    AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id, component

  UNION ALL

  -- Respiratory rate
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    'respiratory_rate' AS component,
    AVG(c.valuenum) AS avg_value,
    MAX(c.valuenum) AS max_value,
    MIN(c.valuenum) AS min_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays i
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
  WHERE
    di.label = 'Respiratory Rate'
    AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id, component

  UNION ALL

  -- Systolic blood pressure
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    'systolic_bp' AS component,
    AVG(c.valuenum) AS avg_value,
    MAX(c.valuenum) AS max_value,
    MIN(c.valuenum) AS min_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays i
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
  WHERE
    di.label = 'Non Invasive Blood Pressure systolic'
    AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id, component

  UNION ALL

  -- Oxygen saturation
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    'oxygen_saturation' AS component,
    AVG(c.valuenum) AS avg_value,
    MAX(c.valuenum) AS max_value,
    MIN(c.valuenum) AS min_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays i
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
  WHERE
    di.label = 'SpO2'
    AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id, component

  UNION ALL

  -- Lactate (from labevents)
  SELECT
    l.subject_id,
    l.hadm_id,
    i.stay_id,
    'lactate' AS component,
    AVG(l.valuenum) AS avg_value,
    MAX(l.valuenum) AS max_value,
    MIN(l.valuenum) AS min_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    icu_stays i
    ON l.subject_id = i.subject_id AND l.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE
    dl.label = 'Lactate'
    AND l.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY
    l.subject_id, l.hadm_id, i.stay_id, component

  UNION ALL

  -- Creatinine
  SELECT
    l.subject_id,
    l.hadm_id,
    i.stay_id,
    'creatinine' AS component,
    AVG(l.valuenum) AS avg_value,
    MAX(l.valuenum) AS max_value,
    MIN(l.valuenum) AS min_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    icu_stays i
    ON l.subject_id = i.subject_id AND l.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE
    dl.label = 'Creatinine'
    AND l.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY
    l.subject_id, l.hadm_id, i.stay_id, component
),

-- Calculate composite instability score for each patient
patient_instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    -- Simple scoring system (can be adjusted based on clinical relevance)
    (COALESCE(MAX(CASE WHEN component = 'heart_rate' THEN max_value END), 0) * 0.1 +
     COALESCE(MAX(CASE WHEN component = 'respiratory_rate' THEN max_value END), 0) * 0.1 +
     (120 - COALESCE(MIN(CASE WHEN component = 'systolic_bp' THEN min_value END), 120)) * 0.2 +
     (100 - COALESCE(MIN(CASE WHEN component = 'oxygen_saturation' THEN min_value END), 100)) * 0.3 +
     COALESCE(MAX(CASE WHEN component = 'lactate' THEN max_value END), 0) * 0.5 +
     COALESCE(MAX(CASE WHEN component = 'creatinine' THEN max_value END), 0) * 0.2) AS instability_score
  FROM
    instability_components
  GROUP BY
    subject_id, hadm_id, stay_id
),

-- Calculate 90th percentile threshold
percentile_threshold AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS threshold
  FROM
    patient_instability_scores
  LIMIT 1
),

-- Get patients at/above 90th percentile
high_instability_patients AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.instability_score,
    a.hospital_expire_flag,
    a.los_hours
  FROM
    patient_instability_scores p
  JOIN
    ards_patients a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  CROSS JOIN
    percentile_threshold t
  WHERE
    p.instability_score >= t.threshold
),

-- Compare lab rates between high instability and general population
lab_comparison AS (
  SELECT
    'High Instability' AS group_name,
    COUNT(DISTINCT l.subject_id) AS patient_count,
    COUNT(DISTINCT CASE WHEN dl.label = 'Lactate' THEN l.labevent_id END) AS lactate_count,
    COUNT(DISTINCT CASE WHEN dl.label = 'Creatinine' THEN l.labevent_id END) AS creatinine_count,
    COUNT(DISTINCT CASE WHEN dl.label = 'Troponin' THEN l.labevent_id END) AS troponin_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    high_instability_patients h
    ON l.subject_id = h.subject_id AND l.hadm_id = h.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE
    dl.label IN ('Lactate', 'Creatinine', 'Troponin')

  UNION ALL

  SELECT
    'General Population' AS group_name,
    COUNT(DISTINCT l.subject_id) AS patient_count,
    COUNT(DISTINCT CASE WHEN dl.label = 'Lactate' THEN l.labevent_id END) AS lactate_count,
    COUNT(DISTINCT CASE WHEN dl.label = 'Creatinine' THEN l.labevent_id END) AS creatinine_count,
    COUNT(DISTINCT CASE WHEN dl.label = 'Troponin' THEN l.labevent_id END) AS troponin_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON l.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND dl.label IN ('Lactate', 'Creatinine', 'Troponin')
)

-- Final results
SELECT
  '90th Percentile Instability Score' AS metric,
  (SELECT threshold FROM percentile_threshold) AS value
UNION ALL
SELECT
  'Mortality Rate (High Instability)' AS metric,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS value
FROM
  high_instability_patients
UNION ALL
SELECT
  'Mean LOS (High Instability)' AS metric,
  ROUND(AVG(los_hours), 2) AS value
FROM
  high_instability_patients
UNION ALL
SELECT
  'Lactate Rate (High Instability)' AS metric,
  ROUND(100 * SUM(lactate_count) / SUM(patient_count), 2) AS value
FROM
  lab_comparison
WHERE
  group_name = 'High Instability'
UNION ALL
SELECT
  'Lactate Rate (General Population)' AS metric,
  ROUND(100 * SUM(lactate_count) / SUM(patient_count), 2) AS value
FROM
  lab_comparison
WHERE
  group_name = 'General Population'
UNION ALL
SELECT
  'Creatinine Rate (High Instability)' AS metric,
  ROUND(100 * SUM(creatinine_count) / SUM(patient_count), 2) AS value
FROM
  lab_comparison
WHERE
  group_name = 'High Instability'
UNION ALL
SELECT
  'Creatinine Rate (General Population)' AS metric,
  ROUND(100 * SUM(creatinine_count) / SUM(patient_count), 2) AS value
FROM
  lab_comparison
WHERE
  group_name = 'General Population';