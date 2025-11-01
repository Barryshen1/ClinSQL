WITH
-- Define lower GI bleeding ICD codes (K55-K64 range)
lower_gi_bleed_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code BETWEEN 'K550' AND 'K649'
),

-- Get male patients aged 89-99 with lower GI bleeding
target_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN lower_gi_bleed_codes lgib ON d.icd_code = lgib.icd_code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
),

-- Get relevant lab tests for instability score
relevant_labs AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label IN (
    'Hemoglobin', 'Hematocrit', 'Platelet Count', 'White Blood Cells',
    'Sodium', 'Potassium', 'Chloride', 'Glucose', 'BUN', 'Creatinine',
    'Lactate', 'INR(PT)', 'PTT', 'pH', 'PaO2', 'PaCO2', 'Bicarbonate'
  )
),

-- Get lab values within first 72 hours of admission
early_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    d.label
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN target_patients t ON l.subject_id = t.subject_id AND l.hadm_id = t.hadm_id
  JOIN relevant_labs r ON l.itemid = r.itemid
  WHERE TIMESTAMP_DIFF(l.charttime, t.admittime, HOUR) <= 72
),

-- Calculate lab instability score (simple approach: count of abnormal values)
lab_scores AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(CASE
      WHEN (label = 'Hemoglobin' AND valuenum < 10) THEN 1
      WHEN (label = 'Hematocrit' AND valuenum < 30) THEN 1
      WHEN (label = 'Platelet Count' AND (valuenum < 150 OR valuenum > 450)) THEN 1
      WHEN (label = 'White Blood Cells' AND (valuenum < 4 OR valuenum > 11)) THEN 1
      WHEN (label = 'Sodium' AND (valuenum < 135 OR valuenum > 145)) THEN 1
      WHEN (label = 'Potassium' AND (valuenum < 3.5 OR valuenum > 5.0)) THEN 1
      WHEN (label = 'Creatinine' AND valuenum > 1.2) THEN 1
      WHEN (label = 'Lactate' AND valuenum > 2.0) THEN 1
      WHEN (label = 'INR(PT)' AND valuenum > 1.1) THEN 1
      WHEN (label = 'PTT' AND valuenum > 35) THEN 1
      WHEN (label = 'pH' AND (valuenum < 7.35 OR valuenum > 7.45)) THEN 1
      WHEN (label = 'PaO2' AND valuenum < 60) THEN 1
      WHEN (label = 'PaCO2' AND valuenum > 45) THEN 1
      WHEN (label = 'Bicarbonate' AND (valuenum < 22 OR valuenum > 26)) THEN 1
      ELSE 0
    END) AS abnormal_count
  FROM early_labs
  GROUP BY subject_id, hadm_id
),

-- Add quintiles to the scores
scores_with_quintiles AS (
  SELECT
    *,
    NTILE(5) OVER(ORDER BY abnormal_count) AS quintile
  FROM lab_scores
),

-- Get outcomes (LOS and mortality)
outcomes AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.abnormal_count,
    s.quintile,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag AS in_hospital_mortality,
    p.dod IS NOT NULL AS overall_mortality
  FROM scores_with_quintiles s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON s.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON s.subject_id = p.subject_id
),

-- Calculate critical lab rates by quintile
quintile_rates AS (
  SELECT
    quintile,
    COUNT(*) AS patient_count,
    AVG(los_days) AS avg_los,
    SUM(CASE WHEN in_hospital_mortality THEN 1 ELSE 0 END) AS in_hosp_deaths,
    SUM(CASE WHEN overall_mortality THEN 1 ELSE 0 END) AS total_deaths,
    AVG(abnormal_count) AS avg_abnormal_labs
  FROM outcomes
  GROUP BY quintile
),

-- Calculate overall critical lab rate
overall_rate AS (
  SELECT
    COUNT(*) AS total_patients,
    AVG(abnormal_count) AS overall_avg_abnormal_labs
  FROM lab_scores
)

-- Final results
SELECT
  q.quintile,
  q.patient_count,
  q.avg_los,
  q.in_hosp_deaths,
  q.total_deaths,
  q.avg_abnormal_labs,
  o.overall_avg_abnormal_labs,
  q.avg_abnormal_labs / o.overall_avg_abnormal_labs AS rate_ratio
FROM quintile_rates q
CROSS JOIN overall_rate o
ORDER BY q.quintile;