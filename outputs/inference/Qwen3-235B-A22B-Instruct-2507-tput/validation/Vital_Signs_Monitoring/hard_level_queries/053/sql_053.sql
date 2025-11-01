WITH patient_cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),

-- Identify ICU stays and flag if associated admission had a shock diagnosis
icu_stays_with_shock AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los AS icu_los,
    a.hospital_expire_flag,
    -- Flag if any shock diagnosis in this admission
    MAX(CASE 
          WHEN LOWER(d.long_title) LIKE '%shock%' THEN 1 
          ELSE 0 
        END) AS has_shock
  FROM `physionet-data.mimiciv_3_1_icu`.icustays ie
  INNER JOIN patient_cohort pc ON ie.subject_id = pc.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a 
    ON ie.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di 
    ON a.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d 
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id, ie.intime, ie.outtime, ie.los, a.hospital_expire_flag
),

-- Extract vital signs (HR, MAP) within first 24 hours of ICU stay
vital_events AS (
  SELECT 
    ce.stay_id,
    di.label,
    ce.valuenum,
    ce.charttime,
    DATETIME_DIFF(ce.charttime, ist.intime, HOUR) AS hours_since_icu_intime
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN icu_stays_with_shock ist ON ce.stay_id = ist.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di ON ce.itemid = di.itemid
  WHERE di.label IN ('Heart Rate', 'Mean Blood Pressure')
    AND ce.charttime >= ist.intime
    AND ce.charttime <= DATETIME_ADD(ist.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),

-- Aggregate counts of abnormal vitals per ICU stay
vital_stats AS (
  SELECT 
    ist.stay_id,
    ist.has_shock,
    ist.icu_los,
    ist.hospital_expire_flag,
    -- Count total and abnormal MAP measurements
    COUNT(CASE WHEN ve.label = 'Mean Blood Pressure' THEN 1 END) AS map_count,
    COUNT(CASE WHEN ve.label = 'Mean Blood Pressure' AND ve.valuenum < 65 THEN 1 END) AS map_lt_65_count,
    -- Count total and abnormal HR measurements
    COUNT(CASE WHEN ve.label = 'Heart Rate' THEN 1 END) AS hr_count,
    COUNT(CASE WHEN ve.label = 'Heart Rate' AND ve.valuenum > 100 THEN 1 END) AS hr_gt_100_count,
    -- Composite instability: any time either MAP < 65 or HR > 100
    COUNT(CASE WHEN (ve.label = 'Mean Blood Pressure' AND ve.valuenum < 65)
                OR (ve.label = 'Heart Rate' AND ve.valuenum > 100) THEN 1 END) AS instability_count,
    COUNT(*) AS total_vital_count
  FROM icu_stays_with_shock ist
  LEFT JOIN vital_events ve ON ist.stay_id = ve.stay_id
  GROUP BY ist.stay_id, ist.has_shock, ist.icu_los, ist.hospital_expire_flag
),

-- Final summary: mean and percentile statistics by shock group
summary_stats AS (
  SELECT 
    has_shock,
    -- ICU Length of Stay (LOS)
    AVG(icu_los) AS mean_icu_los,
    APPROX_QUANTILES(icu_los, 100 IGNORE NULLS)[OFFSET(50)] AS median_icu_los,
    APPROX_QUANTILES(icu_los, 100 IGNORE NULLS)[OFFSET(25)] AS q25_icu_los,
    APPROX_QUANTILES(icu_los, 100 IGNORE NULLS)[OFFSET(75)] AS q75_icu_los,
    -- In-hospital mortality rate
    AVG(hospital_expire_flag) AS mortality_rate,
    -- Hypotension burden: % of MAP measurements < 65
    AVG(CASE WHEN map_count > 0 THEN map_lt_65_count / map_count ELSE NULL END) AS mean_hypotension_burden,
    APPROX_QUANTILES(CASE WHEN map_count > 0 THEN map_lt_65_count / map_count END, 100 IGNORE NULLS)[OFFSET(50)] AS median_hypotension_burden,
    -- Tachycardia burden: % of HR measurements > 100
    AVG(CASE WHEN hr_count > 0 THEN hr_gt_100_count / hr_count ELSE NULL END) AS mean_tachycardia_burden,
    APPROX_QUANTILES(CASE WHEN hr_count > 0 THEN hr_gt_100_count / hr_count END, 100 IGNORE NULLS)[OFFSET(50)] AS median_tachycardia_burden,
    -- Composite instability burden: % of vital checks with instability
    AVG(CASE WHEN total_vital_count > 0 THEN instability_count / total_vital_count ELSE NULL END) AS mean_instability_burden,
    APPROX_QUANTILES(CASE WHEN total_vital_count > 0 THEN instability_count / total_vital_count END, 100 IGNORE NULLS)[OFFSET(50)] AS median_instability_burden
  FROM vital_stats
  GROUP BY has_shock
)

-- Final output
SELECT * FROM summary_stats
ORDER BY has_shock;