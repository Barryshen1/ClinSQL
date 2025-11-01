WITH
-- Define ischemic stroke ICD codes
ischemic_stroke_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code LIKE '433.%' AND icd_code LIKE '%.1')
    OR (icd_version = 9 AND icd_code LIKE '434.%' AND icd_code LIKE '%.1')
    OR (icd_version = 9 AND icd_code = '436')
    OR (icd_version = 10 AND icd_code LIKE 'I63.%')
),

-- Get male inpatients aged 49-59 with ischemic stroke
stroke_patients AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN ischemic_stroke_codes s ON d.icd_code = s.icd_code AND d.icd_version =
    CASE
      WHEN s.icd_code LIKE '433.%' OR s.icd_code LIKE '434.%' OR s.icd_code = '436' THEN 9
      WHEN s.icd_code LIKE 'I63.%' THEN 10
    END
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
),

-- Get relevant lab items for instability score
relevant_labs AS (
  SELECT itemid, label, ref_range_lower, ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label IN (
    'Glucose', 'Sodium', 'Potassium', 'Creatinine', 'White Blood Cells',
    'Hemoglobin', 'Platelet Count', 'INR(PT)', 'PTT', 'BUN', 'pH'
  )
),

-- Get lab values within 72 hours of admission for stroke patients
early_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    r.label,
    r.ref_range_lower,
    r.ref_range_upper,
    TIMESTAMP_DIFF(l.charttime, a.admittime, HOUR) AS hours_since_admission
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN stroke_patients s ON l.subject_id = s.subject_id AND l.hadm_id = s.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON s.hadm_id = a.hadm_id
  JOIN relevant_labs r ON l.itemid = r.itemid
  WHERE TIMESTAMP_DIFF(l.charttime, a.admittime, HOUR) <= 72
    AND l.valuenum IS NOT NULL
),

-- Calculate lab instability score for each patient
lab_instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(
      CASE
        WHEN valuenum < ref_range_lower THEN POWER((ref_range_lower - valuenum)/ref_range_lower, 2)
        WHEN valuenum > ref_range_upper THEN POWER((valuenum - ref_range_upper)/ref_range_upper, 2)
        ELSE 0
      END
    ) AS instability_score
  FROM early_labs
  GROUP BY subject_id, hadm_id
),

-- Calculate 75th percentile of instability scores
percentile_75 AS (
  SELECT PERCENTILE_CONT(instability_score, 0.75) OVER() AS p75
  FROM lab_instability_scores
  LIMIT 1
),

-- Identify high-instability stroke patients
high_instability_stroke AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.instability_score,
    a.los,
    a.hospital_expire_flag,
    p.dod
  FROM lab_instability_scores s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON s.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON s.subject_id = p.subject_id
  CROSS JOIN percentile_75 p
  WHERE s.instability_score > p.p75
),

-- Get age-matched controls (male inpatients 49-59 without ischemic stroke)
controls AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND p.subject_id NOT IN (SELECT subject_id FROM stroke_patients)
),

-- Get lab values for controls
control_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    r.label,
    r.ref_range_lower,
    r.ref_range_upper,
    TIMESTAMP_DIFF(l.charttime, a.admittime, HOUR) AS hours_since_admission
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN controls c ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  JOIN relevant_labs r ON l.itemid = r.itemid
  WHERE TIMESTAMP_DIFF(l.charttime, a.admittime, HOUR) <= 72
    AND l.valuenum IS NOT NULL
),

-- Calculate abnormal lab rates for high-instability stroke vs controls
lab_comparison AS (
  SELECT
    'High-Instability Stroke' AS group_name,
    label,
    COUNT(CASE WHEN valuenum < ref_range_lower OR valuenum > ref_range_upper THEN 1 END) * 100.0 /
      COUNT(*) AS abnormal_rate
  FROM early_labs
  GROUP BY label

  UNION ALL

  SELECT
    'Age-Matched Controls' AS group_name,
    label,
    COUNT(CASE WHEN valuenum < ref_range_lower OR valuenum > ref_range_upper THEN 1 END) * 100.0 /
      COUNT(*) AS abnormal_rate
  FROM control_labs
  GROUP BY label
)

-- Final results
SELECT
  (SELECT p75 FROM percentile_75) AS percentile_75_instability_score,
  (SELECT AVG(los) FROM high_instability_stroke) AS avg_los_high_instability,
  (SELECT AVG(CASE WHEN hospital_expire_flag = 1 OR dod IS NOT NULL THEN 1 ELSE 0 END) FROM high_instability_stroke) AS mortality_rate_high_instability,
  group_name,
  label,
  abnormal_rate
FROM lab_comparison
ORDER BY group_name, label;