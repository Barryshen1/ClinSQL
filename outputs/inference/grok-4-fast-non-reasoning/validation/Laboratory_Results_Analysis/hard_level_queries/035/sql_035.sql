WITH cohort_stroke AS (
  -- Stroke cohort: females 78-88 with acute ischemic stroke
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I63%'
    AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
),

lab_instability AS (
  -- Compute instability flags for critical labs in first 72 hours
  SELECT 
    le.subject_id,
    le.hadm_id,
    SUM(CASE 
      WHEN le.valuenum IS NOT NULL 
        AND (le.valuenum < li.ref_range_lower OR le.valuenum > li.ref_range_upper)
        AND li.ref_range_lower IS NOT NULL AND li.ref_range_upper IS NOT NULL
      THEN 1 
      ELSE 0 
    END) AS total_unstable_labs
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON CAST(le.itemid AS STRING) = li.itemid
  INNER JOIN cohort_stroke cs
    ON le.subject_id = cs.subject_id AND le.hadm_id = cs.hadm_id
  WHERE le.itemid IN (50893, 50971, 50902, 51006, 50912, 5131, 51222, 51265, 50931)  -- Critical labs
    AND DATE_DIFF(le.charttime, cs.admittime, HOUR) <= 72
  GROUP BY le.subject_id, le.hadm_id
),

cohort_metrics AS (
  -- Aggregate for stroke cohort
  SELECT 
    'Stroke Cohort' AS group_type,
    COUNT(DISTINCT cs.hadm_id) AS num_admissions,
    MIN(COALESCE(li.total_unstable_labs, 0)) AS min_72h_instability_score,
    AVG(COALESCE(li.total_unstable_labs, 0)) AS avg_critical_lab_events,
    AVG(COALESCE(cs.los_days, 0)) AS avg_los_days,
    AVG(cs.hospital_expire_flag) AS mortality_rate
  FROM cohort_stroke cs
  LEFT JOIN lab_instability li
    ON cs.subject_id = li.subject_id AND cs.hadm_id = li.hadm_id
),

general_cohort AS (
  -- General cohort: females 78-88, no stroke filter
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
    AND NOT EXISTS (
      -- Exclude stroke admissions
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id 
        AND d.icd_version = '10' 
        AND d.icd_code LIKE 'I63%'
    )
),

general_lab_instability AS (
  -- Instability for general cohort (same logic)
  SELECT 
    le.subject_id,
    le.hadm_id,
    SUM(CASE 
      WHEN le.valuenum IS NOT NULL 
        AND (le.valuenum < li.ref_range_lower OR le.valuenum > li.ref_range_upper)
        AND li.ref_range_lower IS NOT NULL AND li.ref_range_upper IS NOT NULL
      THEN 1 
      ELSE 0 
    END) AS total_unstable_labs
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON CAST(le.itemid AS STRING) = li.itemid
  INNER JOIN general_cohort gc
    ON le.subject_id = gc.subject_id AND le.hadm_id = gc.hadm_id
  WHERE le.itemid IN (50893, 50971, 50902, 51006, 50912, 5131, 51222, 51265, 50931)
    AND DATE_DIFF(le.charttime, gc.admittime, HOUR) <= 72
  GROUP BY le.subject_id, le.hadm_id
),

general_metrics AS (
  -- Aggregate for general cohort
  SELECT 
    'General Inpatients' AS group_type,
    COUNT(DISTINCT gc.hadm_id) AS num_admissions,
    NULL AS min_72h_instability_score,  -- Not requested for general
    AVG(COALESCE(gli.total_unstable_labs, 0)) AS avg_critical_lab_events,
    NULL AS avg_los_days,  -- Not requested for general
    AVG(gc.hospital_expire_flag) AS mortality_rate
  FROM general_cohort gc
  LEFT JOIN general_lab_instability gli
    ON gc.subject_id = gli.subject_id AND gc.hadm_id = gli.hadm_id
)

-- Combine and select key results
SELECT 
  cm.min_72h_instability_score,
  cm.avg_critical_lab_events AS stroke_avg_critical_labs,
  cm.avg_los_days,
  cm.mortality_rate AS stroke_mortality_rate,
  gm.avg_critical_lab_events AS general_avg_critical_labs,
  gm.mortality_rate AS general_mortality_rate
FROM cohort_metrics cm
CROSS JOIN general_metrics gm
WHERE cm.group_type = 'Stroke Cohort';