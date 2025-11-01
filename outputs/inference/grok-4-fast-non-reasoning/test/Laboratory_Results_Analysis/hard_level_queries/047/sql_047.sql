WITH cohort AS (
  -- Base ARDS cohort: males 71-81
  SELECT DISTINCT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn  -- First admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id AND d.seq_num <= 5
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND LOWER(icd.long_title) LIKE '%acute respiratory distress syndrome%'
    AND p.anchor_age IS NOT NULL
),
first_stay AS (
  -- First ICU stay per admission (if any)
  SELECT 
    c.subject_id,
    c.hadm_id,
    i.stay_id,
    i.intime
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
  WHERE c.rn = 1
    AND i.stay_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.subject_id, c.hadm_id ORDER BY i.intime) = 1
),
vitals AS (
  -- Relevant vitals in first 72h of ICU stay
  SELECT 
    fs.subject_id,
    ce.charttime,
    ce.valuenum
  FROM first_stay fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON fs.stay_id = ce.stay_id
  WHERE ce.itemid IN (220045, 220210, 220277)  -- HR, RESP, SpO2
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fs.intime 
    AND EXTRACT(HOUR FROM (ce.charttime - fs.intime)) <= 72
    AND ce.valueuom IN ('/min', '%')  -- Expected units
),
patient_scores AS (
  -- Instability score: CV across all vitals per patient
  SELECT 
    subject_id,
    STDDEV(valuenum) / AVG(valuenum) AS instability_score
  FROM vitals
  GROUP BY subject_id
  HAVING AVG(valuenum) > 0  -- Avoid div by zero
    AND COUNT(*) >= 5  -- Sufficient measurements
),
threshold AS (
  SELECT 
    PERCENTILE_CONT(0.9, instability_score) OVER() AS thresh_90
  FROM patient_scores
),
high_risk AS (
  -- Patients >= threshold, joined back to cohort
  SELECT 
    c.*,
    ps.instability_score
  FROM cohort c
  INNER JOIN patient_scores ps ON c.subject_id = ps.subject_id
  CROSS JOIN threshold t
  WHERE c.rn = 1
    AND ps.instability_score >= t.thresh_90
),
general_cohort AS (
  -- All male inpatients 71-81 for lab comparison
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND p.anchor_age IS NOT NULL
),
lab_abnormals AS (
  -- Critical labs in first 24h (for high-risk and general)
  SELECT 
    'high_risk' AS group_type,
    hr.subject_id,
    le.itemid,
    le.valuenum,
    di.label
  FROM high_risk hr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON hr.subject_id = le.subject_id AND hr.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE le.charttime >= hr.admittime 
    AND EXTRACT(HOUR FROM (le.charttime - hr.admittime)) <= 24
    AND le.valuenum IS NOT NULL
    AND le.itemid IN (50912, 26464, 51265, 50819)  -- Creatinine, WBC, Platelets, PaO2

  UNION ALL

  SELECT 
    'general' AS group_type,
    gc.subject_id,
    le.itemid,
    le.valuenum,
    di.label
  FROM general_cohort gc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON gc.subject_id = le.subject_id AND gc.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE le.charttime >= gc.admittime 
    AND EXTRACT(HOUR FROM (le.charttime - gc.admittime)) <= 24
    AND le.valuenum IS NOT NULL
    AND le.itemid IN (50912, 26464, 51265, 50819)
),
abnormal_flags AS (
  -- Flag abnormal values per patient-lab
  SELECT 
    la.group_type,
    la.subject_id,
    la.label,
    la.itemid,
    CASE 
      WHEN la.itemid = 50912 AND la.valuenum > 1.5 THEN 1  -- Creatinine mg/dL
      WHEN la.itemid = 26464 AND (la.valuenum < 4 OR la.valuenum > 12) THEN 1  -- WBC x10^3/uL
      WHEN la.itemid = 51265 AND la.valuenum < 150 THEN 1  -- Platelets x10^3/uL
      WHEN la.itemid = 50819 AND la.valuenum < 60 THEN 1  -- PaO2 mmHg
      ELSE 0 
    END AS is_abnormal
  FROM lab_abnormals la
),
lab_rates AS (
  SELECT 
    label,
    group_type,
    ROUND(AVG(is_abnormal) * 100, 2) AS abnormal_rate_pct,
    COUNT(DISTINCT subject_id) AS n_patients
  FROM abnormal_flags
  GROUP BY label, group_type
  HAVING n_patients > 0
),
pivoted_labs AS (
  -- Pivot for comparison
  SELECT 
    label,
    COALESCE(MAX(CASE WHEN group_type = 'high_risk' THEN abnormal_rate_pct END), 0) AS high_risk_rate_pct,
    COALESCE(MAX(CASE WHEN group_type = 'general' THEN abnormal_rate_pct END), 0) AS general_rate_pct,
    COALESCE(MAX(CASE WHEN group_type = 'high_risk' THEN abnormal_rate_pct END), 0) - 
    COALESCE(MAX(CASE WHEN group_type = 'general' THEN abnormal_rate_pct END), 0) AS difference_pct
  FROM lab_rates
  GROUP BY label
),
summary_metrics AS (
  SELECT '90th Percentile Threshold' AS metric, CAST(ROUND(thresh_90, 4) AS STRING) AS value, NULL AS high_risk_pct, NULL AS general_pct, NULL AS difference
  FROM threshold
  UNION ALL
  SELECT 'High-Risk Mortality %' AS metric, CAST(ROUND(AVG(hospital_expire_flag) * 100, 2) AS STRING) AS value, NULL, NULL, NULL
  FROM high_risk
  UNION ALL
  SELECT 'High-Risk Mean LOS (days)' AS metric, CAST(ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0), 2) AS STRING) AS value, NULL, NULL, NULL
  FROM high_risk
)
-- Main outputs: Summary metrics + Lab comparisons
SELECT * FROM summary_metrics
UNION ALL
SELECT 
  label AS metric, 
  CAST(high_risk_rate_pct AS STRING) || '%' AS value,
  CAST(general_rate_pct AS STRING) || '%' AS high_risk_pct,
  CAST(difference_pct AS STRING) || '%' AS general_pct,
  NULL AS difference
FROM pivoted_labs
ORDER BY 
  CASE 
    WHEN metric LIKE '%Threshold%' THEN 1
    WHEN metric LIKE '%Mortality%' THEN 2
    WHEN metric LIKE '%LOS%' THEN 3
    ELSE 4 
  END,
  metric;