WITH
-- Define status epilepticus ICD codes (G41.*)
status_epilepticus_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
  AND icd_code LIKE 'G41.%'
),

-- Get patients with status epilepticus
se_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN status_epilepticus_codes c ON d.icd_code = c.icd_code
  WHERE a.hadm_id IS NOT NULL
),

-- Get female patients aged 63-73 with status epilepticus
target_patients AS (
  SELECT p.subject_id, p.gender, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN se_patients s ON p.subject_id = s.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 63 AND 73
),

-- Get ICU stays for these patients
target_icustays AS (
  SELECT i.*
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN target_patients t ON i.subject_id = t.subject_id AND i.hadm_id = t.hadm_id
),

-- Get general ICU population (excluding our target group)
general_icu_patients AS (
  SELECT DISTINCT i.subject_id, i.hadm_id, i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  WHERE i.subject_id NOT IN (SELECT subject_id FROM target_patients)
),

-- Vital signs item IDs
vital_signs_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label IN ('Heart Rate', 'Mean Arterial Pressure')
),

-- Calculate vital instability index components for target group
target_vitals AS (
  SELECT
    t.stay_id,
    TIMESTAMP_DIFF(MAX(c.charttime), MIN(c.charttime), HOUR) AS monitoring_hours,
    COUNTIF(c.itemid = (SELECT itemid FROM vital_signs_items WHERE label = 'Heart Rate') AND c.valuenum > 100) AS tachycardia_count,
    COUNTIF(c.itemid = (SELECT itemid FROM vital_signs_items WHERE label = 'Mean Arterial Pressure') AND c.valuenum < 65) AS map_low_count,
    COUNT(*) AS total_measurements
  FROM target_icustays t
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON t.stay_id = c.stay_id
  JOIN vital_signs_items v ON c.itemid = v.itemid
  WHERE c.charttime BETWEEN t.intime AND TIMESTAMP_ADD(t.intime, INTERVAL 72 HOUR)
  GROUP BY t.stay_id
),

-- Calculate vital instability index components for general ICU
general_vitals AS (
  SELECT
    g.stay_id,
    TIMESTAMP_DIFF(MAX(c.charttime), MIN(c.charttime), HOUR) AS monitoring_hours,
    COUNTIF(c.itemid = (SELECT itemid FROM vital_signs_items WHERE label = 'Heart Rate') AND c.valuenum > 100) AS tachycardia_count,
    COUNTIF(c.itemid = (SELECT itemid FROM vital_signs_items WHERE label = 'Mean Arterial Pressure') AND c.valuenum < 65) AS map_low_count,
    COUNT(*) AS total_measurements
  FROM general_icu_patients g
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON g.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON g.stay_id = c.stay_id
  JOIN vital_signs_items v ON c.itemid = v.itemid
  WHERE c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY g.stay_id
),

-- Calculate metrics for target group
target_metrics AS (
  SELECT
    'Target Group' AS group_name,
    COUNT(DISTINCT t.stay_id) AS patient_count,
    AVG(t.los) AS avg_icu_los,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT t.stay_id) AS mortality_rate,
    AVG(tv.tachycardia_count / NULLIF(tv.total_measurements, 0)) AS tachycardia_burden,
    AVG(tv.map_low_count / NULLIF(tv.total_measurements, 0)) AS map_low_burden,
    AVG(tv.tachycardia_count) AS avg_tachycardia_events,
    AVG(tv.map_low_count) AS avg_map_low_events
  FROM target_icustays t
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON t.subject_id = a.subject_id AND t.hadm_id = a.hadm_id
  LEFT JOIN target_vitals tv ON t.stay_id = tv.stay_id
),

-- Calculate metrics for general ICU
general_metrics AS (
  SELECT
    'General ICU' AS group_name,
    COUNT(DISTINCT g.stay_id) AS patient_count,
    AVG(i.los) AS avg_icu_los,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT g.stay_id) AS mortality_rate,
    AVG(gv.tachycardia_count / NULLIF(gv.total_measurements, 0)) AS tachycardia_burden,
    AVG(gv.map_low_count / NULLIF(gv.total_measurements, 0)) AS map_low_burden,
    AVG(gv.tachycardia_count) AS avg_tachycardia_events,
    AVG(gv.map_low_count) AS avg_map_low_events
  FROM general_icu_patients g
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON g.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON g.subject_id = a.subject_id AND g.hadm_id = a.hadm_id
  LEFT JOIN general_vitals gv ON g.stay_id = gv.stay_id
)

-- Final comparison
SELECT * FROM target_metrics
UNION ALL
SELECT * FROM general_metrics
ORDER BY group_name;