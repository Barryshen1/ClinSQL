WITH cohort AS (
  -- Women 74-84 with primary ICH admission (first per patient)
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
    AND a.admittime >= '2008-01-01'
    AND (
      (d.icd_version = '10' AND d.icd_code LIKE 'I61%') 
      OR d.icd_code = '431'
    )
    AND a.admission_type IN ('EMERGENCY', 'URGENT')
  QUALIFY rn = 1
),

lab_abnormals AS (
  -- Abnormal labs in first 72h for cohort (using clinical thresholds)
  SELECT DISTINCT
    c.hadm_id,
    l.itemid
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.subject_id = l.subject_id 
    AND c.hadm_id = l.hadm_id
    AND l.charttime >= c.admittime
    AND l.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  WHERE l.valuenum IS NOT NULL
    AND li.category IN ('Chemistry', 'Hematology', 'Coagulation', 'Blood Gases')
    AND li.label IS NOT NULL
    AND li.label IN (
      'Sodium', 'Potassium', 'Glucose', 'BUN', 'Creatinine', 
      'INR', 'PTT', 'Platelet count', 'Hemoglobin', 'Arterial pH'
    )
    AND (
      -- Sodium: 135-145 mEq/L
      (li.label = 'Sodium' AND l.valuenum < 135) OR
      (li.label = 'Sodium' AND l.valuenum > 145) OR
      -- Potassium: 3.5-5.0 mEq/L
      (li.label = 'Potassium' AND l.valuenum < 3.5) OR
      (li.label = 'Potassium' AND l.valuenum > 5.0) OR
      -- Glucose: 70-180 mg/dL (adjust for units if needed; assume mg/dL common)
      (li.label = 'Glucose' AND l.valueuom = 'mg/dL' AND l.valuenum < 70) OR
      (li.label = 'Glucose' AND l.valueuom = 'mg/dL' AND l.valuenum > 180) OR
      -- BUN: 7-20 mg/dL
      (li.label = 'BUN' AND l.valuenum < 7) OR
      (li.label = 'BUN' AND l.valuenum > 20) OR
      -- Creatinine: 0.6-1.2 mg/dL
      (li.label = 'Creatinine' AND l.valuenum < 0.6) OR
      (li.label = 'Creatinine' AND l.valuenum > 1.2) OR
      -- INR: >1.5 (elevated for coagulopathy)
      (li.label = 'INR' AND l.valuenum > 1.5) OR
      -- PTT: >40 sec (approximate)
      (li.label = 'PTT' AND l.valuenum > 40) OR
      -- Platelets: <150 x10^3/uL
      (li.label = 'Platelet count' AND l.valuenum < 150) OR
      -- Hemoglobin: <12 g/dL (female)
      (li.label = 'Hemoglobin' AND l.valuenum < 12) OR
      -- pH: 7.35-7.45
      (li.label = 'Arterial pH' AND l.valuenum < 7.35) OR
      (li.label = 'Arterial pH' AND l.valuenum > 7.45)
    )
),

instability_cohort AS (
  SELECT 
    c.*,
    COALESCE(ab.count, 0) AS instability_score,
    DATE_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days
  FROM cohort c
  LEFT JOIN (
    SELECT hadm_id, COUNT(DISTINCT itemid) AS count
    FROM lab_abnormals
    GROUP BY hadm_id
  ) ab ON c.hadm_id = ab.hadm_id
),

quintiles_cohort AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY instability_score) AS quintile
  FROM instability_cohort
),

-- Summary for cohort by quintile
cohort_summary AS (
  SELECT 
    quintile,
    COUNT(*) AS n_cohort,
    AVG(los_days) AS mean_los_cohort,
    SUM(hospital_expire_flag) * 1.0 / COUNT(*) AS mortality_rate_cohort
  FROM quintiles_cohort
  GROUP BY quintile
),

controls_base AS (
  -- Age-matched controls (women 74-84, no ICH, first admission)
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
    AND a.admittime >= '2008-01-01'
    AND a.admission_type IN ('EMERGENCY', 'URGENT')
    AND NOT EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id 
        AND ((d.icd_version = '10' AND d.icd_code LIKE 'I61%') OR d.icd_code = '431')
    )
  QUALIFY rn = 1
),

lab_abnormals_controls AS (
  -- Same abnormal labs logic for controls
  SELECT DISTINCT
    cb.hadm_id,
    l.itemid
  FROM controls_base cb
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON cb.subject_id = l.subject_id 
    AND cb.hadm_id = l.hadm_id
    AND l.charttime >= cb.admittime
    AND l.charttime <= TIMESTAMP_ADD(cb.admittime, INTERVAL 72 HOUR)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  WHERE l.valuenum IS NOT NULL
    AND li.category IN ('Chemistry', 'Hematology', 'Coagulation', 'Blood Gases')
    AND li.label IS NOT NULL
    AND li.label IN (
      'Sodium', 'Potassium', 'Glucose', 'BUN', 'Creatinine', 
      'INR', 'PTT', 'Platelet count', 'Hemoglobin', 'Arterial pH'
    )
    AND (
      -- Same thresholds as cohort
      (li.label = 'Sodium' AND l.valuenum < 135) OR
      (li.label = 'Sodium' AND l.valuenum > 145) OR
      (li.label = 'Potassium' AND l.valuenum < 3.5) OR
      (li.label = 'Potassium' AND l.valuenum > 5.0) OR
      (li.label = 'Glucose' AND l.valueuom = 'mg/dL' AND l.valuenum < 70) OR
      (li.label = 'Glucose' AND l.valueuom = 'mg/dL' AND l.valuenum > 180) OR
      (li.label = 'BUN' AND l.valuenum < 7) OR
      (li.label = 'BUN' AND l.valuenum > 20) OR
      (li.label = 'Creatinine' AND l.valuenum < 0.6) OR
      (li.label = 'Creatinine' AND l.valuenum > 1.2) OR
      (li.label = 'INR' AND l.valuenum > 1.5) OR
      (li.label = 'PTT' AND l.valuenum > 40) OR
      (li.label = 'Platelet count' AND l.valuenum < 150) OR
      (li.label = 'Hemoglobin' AND l.valuenum < 12) OR
      (li.label = 'Arterial pH' AND l.valuenum < 7.35) OR
      (li.label = 'Arterial pH' AND l.valuenum > 7.45)
    )
),

instability_controls AS (
  SELECT 
    cb.*,
    COALESCE(ab.count, 0) AS instability_score,
    DATE_DIFF(cb.dischtime, cb.admittime, HOUR) / 24.0 AS los_days
  FROM controls_base cb
  LEFT JOIN (
    SELECT hadm_id, COUNT(DISTINCT itemid) AS count
    FROM lab_abnormals_controls
    GROUP BY hadm_id
  ) ab ON cb.hadm_id = ab.hadm_id
),

-- Overall control critical rate (any abnormal lab)
control_critical_rate AS (
  SELECT 
    SUM(CASE WHEN instability_score > 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS critical_rate_control
  FROM instability_controls
)

-- Summary for cohort by quintile with control comparison
SELECT 
  cs.quintile,
  cs.n_cohort,
  ROUND(cs.mean_los_cohort, 2) AS mean_los_days,
  ROUND(cs.mortality_rate_cohort * 100, 1) AS mortality_percent,
  ROUND(ccr.critical_rate_control * 100, 1) AS control_critical_lab_rate_percent
FROM cohort_summary cs
CROSS JOIN control_critical_rate ccr
ORDER BY cs.quintile;