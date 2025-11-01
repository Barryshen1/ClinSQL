WITH
-- Step 1: Identify female patients aged 40-50 with ARDS
female_ards_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
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
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND di.icd_code IN ('J80', 'J82') -- ARDS ICD-10 codes
    AND di.long_title LIKE '%acute respiratory distress%'
),

-- Step 2: Calculate lab instability score for first 72 hours of ICU stay
lab_instability_scores AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    SUM(
      CASE
        -- Sodium abnormalities
        WHEN l.itemid = 50824 AND (l.valuenum < 135 OR l.valuenum > 145) THEN 1
        -- Potassium abnormalities
        WHEN l.itemid = 50822 AND (l.valuenum < 3.5 OR l.valuenum > 5.0) THEN 1
        -- Glucose abnormalities
        WHEN l.itemid = 50809 AND (l.valuenum < 70 OR l.valuenum > 180) THEN 1
        -- Hemoglobin abnormalities
        WHEN l.itemid = 50813 AND (l.valuenum < 12 OR l.valuenum > 16) THEN 1
        -- Platelet abnormalities
        WHEN l.itemid = 51265 AND (l.valuenum < 150 OR l.valuenum > 450) THEN 1
        -- pH abnormalities
        WHEN l.itemid = 50818 AND (l.valuenum < 7.35 OR l.valuenum > 7.45) THEN 1
        -- PaO2 abnormalities
        WHEN l.itemid = 50821 AND (l.valuenum < 80) THEN 1
        ELSE 0
      END
    ) AS instability_score
  FROM
    female_ards_patients f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON f.subject_id = l.subject_id AND f.hadm_id = l.hadm_id
  WHERE
    l.charttime BETWEEN f.icu_intime AND DATETIME_ADD(f.icu_intime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id
),

-- Step 3: Calculate 75th percentile of instability scores
percentile_threshold AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.75) OVER() AS p75_threshold
  FROM
    lab_instability_scores
  LIMIT 1
),

-- Step 4: Patients at/above 75th percentile
high_risk_patients AS (
  SELECT
    f.*,
    l.instability_score,
    p.p75_threshold
  FROM
    female_ards_patients f
  JOIN
    lab_instability_scores l
    ON f.subject_id = l.subject_id AND f.hadm_id = l.hadm_id AND f.stay_id = l.stay_id
  CROSS JOIN
    percentile_threshold p
  WHERE
    l.instability_score >= p.p75_threshold
),

-- Step 5: Age-matched non-ARDS female inpatients
non_ards_controls AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE di.icd_code IN ('J80', 'J82')
    )
)

-- Final results
SELECT
  'High Risk ARDS Patients' AS cohort,
  COUNT(DISTINCT h.subject_id) AS patient_count,
  SUM(CASE WHEN h.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT h.subject_id) AS mortality_rate,
  AVG(h.icu_los) AS mean_icu_los,
  (
    SELECT COUNT(l.labevent_id) / COUNT(DISTINCT l.subject_id || '-' || l.hadm_id)
    FROM high_risk_patients hr
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON hr.subject_id = l.subject_id AND hr.hadm_id = l.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
      ON l.itemid = d.itemid
    WHERE d.category IN ('Chemistry', 'Hematology', 'Blood Gas')
  ) AS avg_critical_lab_events
FROM
  high_risk_patients h

UNION ALL

SELECT
  'Non-ARDS Control Patients' AS cohort,
  COUNT(DISTINCT n.subject_id) AS patient_count,
  SUM(CASE WHEN n.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT n.subject_id) AS mortality_rate,
  AVG(n.icu_los) AS mean_icu_los,
  (
    SELECT COUNT(l.labevent_id) / COUNT(DISTINCT l.subject_id || '-' || l.hadm_id)
    FROM non_ards_controls nc
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON nc.subject_id = l.subject_id AND nc.hadm_id = l.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
      ON l.itemid = d.itemid
    WHERE d.category IN ('Chemistry', 'Hematology', 'Blood Gas')
  ) AS avg_critical_lab_events
FROM
  non_ards_controls n
ORDER BY
  cohort;