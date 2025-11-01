WITH stroke_patients AS (
  -- Identify patients with ischemic or hemorrhagic stroke
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.gender,
    p.anchor_age,
    p.dod,
    d.icd_code,
    d.icd_version,
    d.long_title,
    CASE
      WHEN d.icd_code LIKE 'I63%' OR
           (d.icd_version = 9 AND d.icd_code IN ('433.01', '433.11', '433.21', '433.31', '433.81', '433.91', '434.01', '434.11', '434.91', '436'))
      THEN 'Ischemic'
      WHEN d.icd_code LIKE 'I61%' OR
           (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432.0', '432.1', '432.9'))
      THEN 'Hemorrhagic'
    END AS stroke_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    p.gender = 'M' AND
    p.anchor_age BETWEEN 44 AND 54 AND
    (d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'I61%' OR
     (d.icd_version = 9 AND d.icd_code IN ('433.01', '433.11', '433.21', '433.31', '433.81', '433.91',
                                           '434.01', '434.11', '434.91', '436', '430', '431', '432.0', '432.1', '432.9')))
),

-- Calculate Charlson Comorbidity Index (simplified version)
comorbidity_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(CASE
      WHEN diag.icd_code IN ('410', '412', '428', '414', '425', '427', '426', '421', '429', '416', '413', '411', '415', '423', '424', '420', '422', '417') THEN 1
      WHEN diag.icd_code IN ('430', '431', '432', '433', '434', '435', '436', '437', '438') THEN 1
      WHEN diag.icd_code IN ('157', '155', '156', '153', '154', '158', '159', '150', '151', '152') THEN 2
      WHEN diag.icd_code IN ('250', '250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9') THEN 1
      WHEN diag.icd_code IN ('272.0', '272.1', '272.2', '272.4', '571.2', '571.4', '571.5', '571.6') THEN 1
      ELSE 0
    END) AS cci_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  GROUP BY
    subject_id, hadm_id
),

-- Identify interventions
interventions AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN itemid IN (223900, 223901, 223902) THEN 1 ELSE 0 END) AS mech_vent,
    MAX(CASE WHEN itemid IN (221906, 221907, 221908, 221909, 221910) THEN 1 ELSE 0 END) AS vasopressors,
    MAX(CASE WHEN itemid IN (225158, 225159, 225160, 225161) THEN 1 ELSE 0 END) AS rrt
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  GROUP BY
    subject_id, hadm_id
),

-- Combine all data
combined_data AS (
  SELECT
    sp.subject_id,
    sp.hadm_id,
    sp.stroke_type,
    sp.admittime,
    sp.dischtime,
    sp.deathtime,
    p.dod,
    TIMESTAMP_DIFF(sp.dischtime, sp.admittime, DAY) AS hospital_los,
    cs.cci_score,
    CASE
      WHEN cs.cci_score BETWEEN 0 AND 1 THEN 'Low'
      WHEN cs.cci_score BETWEEN 2 AND 3 THEN 'Medium'
      WHEN cs.cci_score >= 4 THEN 'High'
    END AS comorbidity_level,
    i.mech_vent,
    i.vasopressors,
    i.rrt,
    CASE WHEN sp.deathtime IS NOT NULL OR p.dod IS NOT NULL THEN 1 ELSE 0 END AS mortality
  FROM
    stroke_patients sp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON sp.subject_id = p.subject_id
  LEFT JOIN
    comorbidity_scores cs ON sp.subject_id = cs.subject_id AND sp.hadm_id = cs.hadm_id
  LEFT JOIN
    interventions i ON sp.subject_id = i.subject_id AND sp.hadm_id = i.hadm_id
  WHERE
    sp.stroke_type IS NOT NULL
)

-- Final aggregation
SELECT
  stroke_type,
  CASE WHEN hospital_los <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_category,
  comorbidity_level,
  COUNT(*) AS patient_count,
  ROUND(100 * SUM(mortality) / COUNT(*), 1) AS mortality_percentage,
  ROUND(PERCENTILE_CONT(hospital_los, 0.5) OVER (PARTITION BY stroke_type, los_category, comorbidity_level), 1) AS median_los,
  ROUND(100 * SUM(mech_vent) / COUNT(*), 1) AS mech_vent_percentage,
  ROUND(100 * SUM(vasopressors) / COUNT(*), 1) AS vasopressors_percentage,
  ROUND(100 * SUM(rrt) / COUNT(*), 1) AS rrt_percentage
FROM
  combined_data
GROUP BY
  stroke_type, los_category, comorbidity_level
ORDER BY
  stroke_type, los_category, comorbidity_level;