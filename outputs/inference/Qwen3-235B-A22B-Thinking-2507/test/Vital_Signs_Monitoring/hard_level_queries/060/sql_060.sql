WITH icu_stays AS (
  SELECT 
    icu.subject_id, 
    icu.hadm_id, 
    icu.stay_id,
    icu.intime,
    icu.outtime,
    p.gender,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 78 AND 88
),

hhs_cases AS (
  SELECT DISTINCT icu.stay_id
  FROM icu_stays icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.hadm_id = diag.hadm_id
  WHERE 
    -- ICD-9: '25002' = diabetes with hyperosmolarity
    (diag.icd_version = 9 AND diag.icd_code = '25002')
    OR
    -- ICD-10: hyperosmolar codes (E08.0x-E13.0x) - FIXED: grouped OR conditions
    (diag.icd_version = 10 AND 
        (diag.icd_code LIKE 'E08.0%' 
         OR diag.icd_code LIKE 'E09.0%' 
         OR diag.icd_code LIKE 'E10.0%' 
         OR diag.icd_code LIKE 'E11.0%' 
         OR diag.icd_code LIKE 'E13.0%'))
),

vital_signs AS (
  SELECT 
    ce.stay_id,
    ce.charttime,
    di.label,
    ce.valuenum,
    -- Define abnormal vital signs using standard thresholds - FIXED: replaced ILIKE with LOWER() LIKE
    CASE
      WHEN LOWER(di.label) LIKE '%heart rate%' AND (ce.valuenum < 50 OR ce.valuenum > 100) THEN 1
      WHEN LOWER(di.label) LIKE '%systolic%' AND (ce.valuenum < 90 OR ce.valuenum > 180) THEN 1
      WHEN LOWER(di.label) LIKE '%diastolic%' AND (ce.valuenum < 60 OR ce.valuenum > 110) THEN 1
      WHEN (LOWER(di.label) LIKE '%mean%' AND (LOWER(di.label) LIKE '%blood pressure%' OR LOWER(di.label) LIKE '%arterial%')) 
           AND (ce.valuenum < 65 OR ce.valuenum > 110) THEN 1
      WHEN LOWER(di.label) LIKE '%respiratory rate%' AND (ce.valuenum < 10 OR ce.valuenum > 25) THEN 1
      WHEN LOWER(di.label) LIKE '%temperature%' AND (ce.valuenum < 35 OR ce.valuenum > 39) THEN 1
      WHEN LOWER(di.label) LIKE '%spo2%' AND ce.valuenum < 90 THEN 1
      ELSE 0
    END AS is_abnormal
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  INNER JOIN icu_stays icu
    ON ce.stay_id = icu.stay_id
  WHERE di.category = 'Vital Signs'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
),

patient_metrics AS (
  SELECT 
    icu.stay_id,
    -- Composite instability score = total abnormal measurements
    COUNTIF(vs.is_abnormal = 1) AS composite_instability_score,
    -- Abnormal-vital burden = proportion of abnormal measurements
    SAFE_DIVIDE(COUNTIF(vs.is_abnormal = 1), COUNT(*)) AS abnormal_vital_burden,
    -- ICU LOS in hours
    DATETIME_DIFF(icu.outtime, icu.intime, HOUR) AS icu_los_hours,
    -- Mortality (hospital)
    adm.hospital_expire_flag AS mortality
  FROM icu_stays icu
  LEFT JOIN vital_signs vs
    ON icu.stay_id = vs.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  GROUP BY icu.stay_id, icu.outtime, icu.intime, adm.hospital_expire_flag
),

grouped_metrics AS (
  SELECT 
    pm.*,
    CASE WHEN hc.stay_id IS NOT NULL THEN 'HHS' ELSE 'Control' END AS patient_group
  FROM patient_metrics pm
  LEFT JOIN hhs_cases hc
    ON pm.stay_id = hc.stay_id
)

-- Calculate percentiles for each metric by group - FIXED: replaced GROUP BY with DISTINCT
SELECT DISTINCT
  patient_group,
  -- Composite instability score percentiles
  PERCENTILE_CONT(composite_instability_score, 0.25) OVER (PARTITION BY patient_group) AS instability_25th,
  PERCENTILE_CONT(composite_instability_score, 0.5) OVER (PARTITION BY patient_group) AS instability_median,
  PERCENTILE_CONT(composite_instability_score, 0.75) OVER (PARTITION BY patient_group) AS instability_75th,
  
  -- Abnormal-vital burden percentiles
  PERCENTILE_CONT(abnormal_vital_burden, 0.25) OVER (PARTITION BY patient_group) AS burden_25th,
  PERCENTILE_CONT(abnormal_vital_burden, 0.5) OVER (PARTITION BY patient_group) AS burden_median,
  PERCENTILE_CONT(abnormal_vital_burden, 0.75) OVER (PARTITION BY patient_group) AS burden_75th,
  
  -- ICU LOS percentiles
  PERCENTILE_CONT(icu_los_hours, 0.25) OVER (PARTITION BY patient_group) AS los_25th,
  PERCENTILE_CONT(icu_los_hours, 0.5) OVER (PARTITION BY patient_group) AS los_median,
  PERCENTILE_CONT(icu_los_hours, 0.75) OVER (PARTITION BY patient_group) AS los_75th,
  
  -- Mortality percentiles (for binary data)
  PERCENTILE_CONT(mortality, 0.25) OVER (PARTITION BY patient_group) AS mortality_25th,
  PERCENTILE_CONT(mortality, 0.5) OVER (PARTITION BY patient_group) AS mortality_median,
  PERCENTILE_CONT(mortality, 0.75) OVER (PARTITION BY patient_group) AS mortality_75th
FROM grouped_metrics;