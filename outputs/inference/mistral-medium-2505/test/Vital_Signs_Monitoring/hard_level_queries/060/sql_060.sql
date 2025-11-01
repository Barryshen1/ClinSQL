WITH
-- Get patient demographics and ICU stays
patient_icu_data AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours,
    -- Calculate age at admission (approximate)
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
),

-- Identify HHS patients (Hyperosmolar Hyperglycemic State)
hhs_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    d.icd_code IN ('E1100', 'E1101', 'E1109', 'E1110', 'E1111', 'E1119') -- HHS ICD-10 codes
),

-- Create age-matched controls (non-HHS patients)
controls AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id
  FROM
    patient_icu_data p
  WHERE
    p.subject_id NOT IN (SELECT subject_id FROM hhs_patients)
),

-- Get vital signs during first 48 hours of ICU stay
vital_signs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum,
    d.label AS vital_sign,
    d.lownormalvalue,
    d.highnormalvalue
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  JOIN
    patient_icu_data p
    ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id AND c.stay_id = p.stay_id
  WHERE
    c.charttime BETWEEN p.icu_intime AND TIMESTAMP_ADD(p.icu_intime, INTERVAL 48 HOUR)
    AND d.category IN ('Vital Signs')
    AND c.valuenum IS NOT NULL
),

-- Calculate abnormal vital signs (1 if abnormal, 0 if normal)
abnormal_vitals AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    vital_sign,
    CASE
      WHEN (valuenum < lownormalvalue OR valuenum > highnormalvalue) THEN 1
      ELSE 0
    END AS is_abnormal
  FROM
    vital_signs
),

-- Calculate composite instability score (sum of abnormal vitals per patient)
composite_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    SUM(is_abnormal) AS composite_instability_score,
    AVG(is_abnormal) AS abnormal_vital_burden
  FROM
    abnormal_vitals
  GROUP BY
    subject_id, hadm_id, stay_id
),

-- Combine all data
final_data AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.age_at_admission,
    p.icu_los_hours,
    p.hospital_expire_flag,
    CASE WHEN h.subject_id IS NOT NULL THEN 'HHS' ELSE 'Control' END AS group_type,
    c.composite_instability_score,
    c.abnormal_vital_burden
  FROM
    patient_icu_data p
  LEFT JOIN
    hhs_patients h
    ON p.subject_id = h.subject_id AND p.hadm_id = h.hadm_id
  LEFT JOIN
    composite_scores c
    ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id AND p.stay_id = c.stay_id
  WHERE
    p.subject_id IN (SELECT subject_id FROM hhs_patients)
    OR p.subject_id IN (SELECT subject_id FROM controls)
)

-- Calculate percentiles and median for each metric
SELECT
  group_type,
  APPROX_QUANTILES(composite_instability_score, 4)[OFFSET(1)] AS composite_instability_25th,
  APPROX_QUANTILES(composite_instability_score, 4)[OFFSET(2)] AS composite_instability_median,
  APPROX_QUANTILES(composite_instability_score, 4)[OFFSET(3)] AS composite_instability_75th,
  APPROX_QUANTILES(abnormal_vital_burden, 4)[OFFSET(1)] AS abnormal_vital_burden_25th,
  APPROX_QUANTILES(abnormal_vital_burden, 4)[OFFSET(2)] AS abnormal_vital_burden_median,
  APPROX_QUANTILES(abnormal_vital_burden, 4)[OFFSET(3)] AS abnormal_vital_burden_75th,
  APPROX_QUANTILES(icu_los_hours, 4)[OFFSET(1)] AS icu_los_25th,
  APPROX_QUANTILES(icu_los_hours, 4)[OFFSET(2)] AS icu_los_median,
  APPROX_QUANTILES(icu_los_hours, 4)[OFFSET(3)] AS icu_los_75th,
  AVG(hospital_expire_flag) AS mortality_rate
FROM
  final_data
GROUP BY
  group_type
ORDER BY
  group_type;