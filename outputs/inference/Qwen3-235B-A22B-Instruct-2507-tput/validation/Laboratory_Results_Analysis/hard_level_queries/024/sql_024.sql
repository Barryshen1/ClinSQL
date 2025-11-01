WITH base_cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 53 AND 63
),

post_arrest AS (
  SELECT DISTINCT bc.*
  FROM base_cohort bc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON bc.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%cardiac arrest%'
),

critical_labs AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems
  WHERE LOWER(label) IN (
    'potassium', 'sodium', 'chloride', 'bicarbonate', 'creatinine', 'urea nitrogen',
    'wbc', 'hgb', 'platelet', 'glucose', 'calcium', 'magnesium', 'ph', 'lactate'
  )
),

lab_48h AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.itemid,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    -- Flag abnormal: outside reference range
    CASE 
      WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper 
      THEN 1 ELSE 0 
    END AS is_abnormal
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN critical_labs cl ON le.itemid = cl.itemid
  INNER JOIN base_cohort bc ON le.hadm_id = bc.hadm_id
  WHERE le.charttime >= bc.admittime
    AND le.charttime <= DATETIME_ADD(bc.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
),

abnormal_count AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNTIF(is_abnormal = 1) AS instability_score
  FROM lab_48h
  GROUP BY subject_id, hadm_id
),

post_arrest_with_score AS (
  SELECT 
    pa.*,
    COALESCE(acs.instability_score, 0) AS instability_score
  FROM post_arrest pa
  LEFT JOIN abnormal_count acs
    ON pa.subject_id = acs.subject_id AND pa.hadm_id = acs.hadm_id
),

percentile_90 AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
  FROM post_arrest_with_score
),

high_instability AS (
  SELECT pas.*
  FROM post_arrest_with_score pas
  CROSS JOIN percentile_90 p
  WHERE pas.instability_score >= p.p90_score
),

-- Final stats for high-instability group
high_instability_stats AS (
  SELECT
    COUNT(*) AS count_high_instability,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / (24*60*60)) AS mean_los_days
  FROM high_instability
),

-- Critical lab frequency: high-instability post-arrest vs all base cohort
lab_frequency_comparison AS (
  -- High-instability post-arrest
  SELECT
    'high_instability_post_arrest' AS group_name,
    COUNT(*) AS total_critical_labs
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN critical_labs cl ON le.itemid = cl.itemid
  INNER JOIN high_instability hi 
    ON le.hadm_id = hi.hadm_id
  WHERE le.charttime >= hi.admittime
    AND le.charttime <= DATETIME_ADD(hi.admittime, INTERVAL 48 HOUR)
  UNION ALL
  -- All base cohort (female 53-63)
  SELECT
    'all_female_53_63' AS group_name,
    COUNT(*) AS total_critical_labs
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN critical_labs cl ON le.itemid = cl.itemid
  INNER JOIN base_cohort bc 
    ON le.hadm_id = bc.hadm_id
  WHERE le.charttime >= bc.admittime
    AND le.charttime <= DATETIME_ADD(bc.admittime, INTERVAL 48 HOUR)
)

-- Final output: combine stats and comparison
SELECT
  h.count_high_instability,
  h.mortality_rate,
  h.mean_los_days,
  l.group_name,
  l.total_critical_labs
FROM high_instability_stats h
CROSS JOIN lab_frequency_comparison l;