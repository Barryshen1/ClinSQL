WITH HHS_Patients AS (
  -- Identify patients with HHS diagnosis
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND d.icd_code = '250.2' -- HHS ICD-10 code
),
Control_Patients AS (
  -- Identify age-matched control patients (without HHS)
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id AND d.icd_code = '250.2'
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND d.icd_code IS NULL -- Exclude patients with HHS
),
ICU_Stays AS (
  -- Get ICU stays for both groups
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  WHERE
    s.subject_id IN (SELECT subject_id FROM HHS_Patients)
    OR s.subject_id IN (SELECT subject_id FROM Control_Patients)
),
Vital_Signs AS (
  -- Get vital signs for the first 48 hours
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.charttime,
    s.valuenum AS value,
    s.valueuom AS unit,
    d.label AS vital_sign_label
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS s
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS d
    ON s.itemid = d.itemid
  WHERE
    s.subject_id IN (SELECT subject_id FROM ICU_Stays)
    AND s.charttime BETWEEN ICU_Stays.intime AND TIMESTAMP_ADD(ICU_Stays.intime, INTERVAL 48 HOUR)
    AND d.label IN ('Heart Rate', 'Systolic Blood Pressure', 'Diastolic Blood Pressure', 'Respiratory Rate', 'Temperature')
),
Instability_Score AS (
  -- Calculate the composite instability score
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    (CASE
      WHEN vital_sign_label = 'Heart Rate' THEN ABS(value - 80)
      WHEN vital_sign_label = 'Systolic Blood Pressure' THEN ABS(value - 120)
      WHEN vital_sign_label = 'Diastolic Blood Pressure' THEN ABS(value - 80)
      WHEN vital_sign_label = 'Respiratory Rate' THEN ABS(value - 12)
      WHEN vital_sign_label = 'Temperature' THEN ABS(value - 37)
      ELSE 0
    END) AS instability_score
  FROM Vital_Signs
),
Abnormal_Vital_Burden AS (
  -- Calculate the burden of abnormal vital signs
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    CASE
      WHEN instability_score > 0 THEN 1
      ELSE 0
    END AS is_abnormal
  FROM Instability_Score
),
Summary_Stats AS (
  -- Calculate summary statistics for each group
  SELECT
    'HHS' AS patient_group,
    PERCENTILE_CONT(instability_score, 0.25) OVER (PARTITION BY subject_id;