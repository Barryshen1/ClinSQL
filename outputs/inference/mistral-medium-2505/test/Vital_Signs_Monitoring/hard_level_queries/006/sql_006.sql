WITH
-- Define UGIB ICD codes (example codes - may need adjustment)
ugib_icd_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN (
    'K25', 'K26', 'K27', 'K28', 'K920', 'K921', 'K922'
  )
),

-- Get patients with UGIB diagnosis
ugib_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN ugib_icd_codes u ON d.icd_code = u.icd_code
  WHERE a.subject_id IN (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
    AND anchor_age BETWEEN 60 AND 70
  )
),

-- Get ICU stays for these patients
ugib_icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime AS icu_intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN ugib_patients u ON i.subject_id = u.subject_id AND i.hadm_id = u.hadm_id
),

-- Get vital signs for these patients in first 48 hours of ICU stay
vital_signs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum,
    di.label,
    TIMESTAMP_DIFF(c.charttime, i.icu_intime, HOUR) AS hours_since_icu_admission
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN ugib_icu_stays i ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON c.itemid = di.itemid
  WHERE di.label IN ('Heart Rate', 'Mean Arterial Pressure', 'Respiratory Rate')
  AND TIMESTAMP_DIFF(c.charttime, i.icu_intime, HOUR) <= 48
),

-- Calculate vital instability index (example calculation - may need adjustment)
vital_instability AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    -- Example instability index calculation (tachycardia + hypotension + tachypnea)
    SUM(CASE WHEN label = 'Heart Rate' AND valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count,
    SUM(CASE WHEN label = 'Mean Arterial Pressure' AND valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_count,
    SUM(CASE WHEN label = 'Respiratory Rate' AND valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea_count,
    COUNT(DISTINCT itemid) AS total_measurements,
    -- Composite instability index (example formula)
    (SUM(CASE WHEN label = 'Heart Rate' AND valuenum > 100 THEN 1 ELSE 0 END) +
     SUM(CASE WHEN label = 'Mean Arterial Pressure' AND valuenum < 65 THEN 1 ELSE 0 END) +
     SUM(CASE WHEN label = 'Respiratory Rate' AND valuenum > 20 THEN 1 ELSE 0 END)) /
    NULLIF(COUNT(DISTINCT itemid), 0) AS instability_index
  FROM vital_signs
  GROUP BY subject_id, hadm_id, stay_id
),

-- Get 95th percentile of instability index
percentile_95 AS (
  SELECT PERCENTILE_CONT(instability_index, 0.95) OVER() AS p95
  FROM vital_instability
  LIMIT 1
),

-- Get top decile patients (instability index >= 95th percentile)
top_decile AS (
  SELECT v.*
  FROM vital_instability v
  CROSS JOIN percentile_95 p
  WHERE v.instability_index >= p.p95
),

-- Get age-matched controls (same age range, no UGIB)
controls AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 60 AND 70
  AND a.subject_id NOT IN (SELECT subject_id FROM ugib_patients)
),

-- Get ICU stays for controls
control_icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime AS icu_intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN controls c ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
),

-- Get vital signs for controls in first 48 hours of ICU stay
control_vital_signs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum,
    di.label,
    TIMESTAMP_DIFF(c.charttime, i.icu_intime, HOUR) AS hours_since_icu_admission
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN control_icu_stays i ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON c.itemid = di.itemid
  WHERE di.label IN ('Heart Rate', 'Mean Arterial Pressure', 'Respiratory Rate')
  AND TIMESTAMP_DIFF(c.charttime, i.icu_intime, HOUR) <= 48
),

-- Calculate outcomes for top decile and controls
outcomes AS (
  SELECT
    'Top Decile' AS group_name,
    COUNT(DISTINCT t.subject_id) AS patient_count,
    SUM(CASE WHEN t.tachycardia_count > 0 THEN 1 ELSE 0 END) AS tachycardia_patients,
    SUM(CASE WHEN t.hypotension_count > 0 THEN 1 ELSE 0 END) AS hypotension_patients,
    SUM(CASE WHEN t.tachypnea_count > 0 THEN 1 ELSE 0 END) AS tachypnea_patients,
    AVG(TIMESTAMP_DIFF(i.outtime, i.intime, HOUR)) AS avg_icu_los,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count
  FROM top_decile t
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON t.subject_id = i.subject_id AND t.hadm_id = i.hadm_id AND t.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON t.subject_id = a.subject_id AND t.hadm_id = a.hadm_id
  GROUP BY group_name

  UNION ALL

  SELECT
    'Controls' AS group_name,
    COUNT(DISTINCT c.subject_id) AS patient_count,
    SUM(CASE WHEN c.label = 'Heart Rate' AND c.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_patients,
    SUM(CASE WHEN c.label = 'Mean Arterial Pressure' AND c.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_patients,
    SUM(CASE WHEN c.label = 'Respiratory Rate' AND c.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea_patients,
    AVG(TIMESTAMP_DIFF(i.outtime, i.intime, HOUR)) AS avg_icu_los,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count
  FROM control_vital_signs c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.subject_id = a.subject_id AND c.hadm_id = a.hadm_id
  GROUP BY group_name
)

-- Final results
SELECT
  group_name,
  patient_count,
  tachycardia_patients,
  hypotension_patients,
  tachypnea_patients,
  avg_icu_los,
  mortality_count,
  mortality_count / patient_count AS mortality_rate
FROM outcomes
ORDER BY group_name;