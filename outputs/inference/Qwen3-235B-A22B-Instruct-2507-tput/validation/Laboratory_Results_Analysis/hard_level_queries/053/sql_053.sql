WITH
  -- Step 1: Define cohort — male, age 68–78, with lower GI bleeding
  cohort AS (
    SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE p.gender = 'M'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 68 AND 78
      AND LOWER(d.long_title) LIKE '%gastrointest%bleed%'
      AND LOWER(d.long_title) LIKE '%lower%'
  ),

  -- Step 2: Get relevant lab items
  target_labs AS (
    SELECT itemid, label
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE LOWER(label) IN ('creatinine', 'potassium', 'platelet count', 'hemoglobin', 'wbc count')
  ),

  -- Step 3: Labs in first 72h with abnormal flags
  labs_72h AS (
    SELECT 
      l.hadm_id,
      l.itemid,
      tl.label,
      l.valuenum,
      l.ref_range_lower,
      l.ref_range_upper,
      CASE 
        WHEN l.valuenum IS NULL THEN NULL
        WHEN l.ref_range_lower IS NOT NULL AND l.ref_range_upper IS NOT NULL AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper) THEN 1
        WHEN l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower THEN 1
        WHEN l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper THEN 1
        ELSE 0
      END AS is_abnormal
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN target_labs tl ON l.itemid = tl.itemid
    JOIN cohort c ON l.hadm_id = c.hadm_id
    WHERE l.charttime >= c.admittime 
      AND l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
      AND l.valuenum IS NOT NULL
  ),

  -- Step 4: Instability score = total abnormal lab results per admission
  instability AS (
    SELECT 
      hadm_id,
      SUM(is_abnormal) AS instability_score
    FROM labs_72h
    WHERE is_abnormal IS NOT NULL
    GROUP BY hadm_id
  ),

  -- Step 5: 90th percentile of instability score
  p90_value AS (
    SELECT 
      APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
    FROM instability
  ),

  -- Step 6: Top-tier patients (instability >= 90th percentile)
  top_tier AS (
    SELECT i.hadm_id
    FROM instability i
    CROSS JOIN p90_value p
    WHERE i.instability_score >= p.p90_score
  ),

  -- Step 7: Aggregate outcomes for top-tier and all cohort
  summary_stats AS (
    SELECT
      'top_tier' AS group_type,
      AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
      AVG(DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0) AS avg_los_days,
      AVG(CASE WHEN l.label = 'creatinine' AND l.is_abnormal = 1 THEN 1 ELSE 0 END) AS abn_cr_rate,
      AVG(CASE WHEN l.label = 'potassium' AND l.is_abnormal = 1 THEN 1 ELSE 0 END) AS abn_k_rate,
      AVG(CASE WHEN l.label = 'platelet count' AND l.is_abnormal = 1 THEN 1 ELSE 0 END) AS abn_platelets_rate,
      AVG(CASE WHEN l.label = 'hemoglobin' AND l.is_abnormal = 1 THEN 1 ELSE 0 END) AS abn_hgb_rate,
      AVG(CASE WHEN l.label = 'wbc count' AND l.is_abnormal = 1 THEN 1 ELSE 0 END) AS abn_wbc_rate
    FROM top_tier tt
    JOIN cohort c ON tt.hadm_id = c.hadm_id
    LEFT JOIN labs_72h l ON c.hadm_id = l.hadm_id
    GROUP BY group_type

    UNION ALL

    SELECT
      'all_cohort' AS group_type,
      AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
      AVG(DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0) AS avg_los_days,
      AVG(CASE WHEN l.label = 'creatinine' AND l.is_abnormal = 1 THEN 1 ELSE 0 END) AS abn_cr_rate,
      AVG(CASE WHEN l.label = 'potassium' AND l.is_abnormal = 1 THEN 1 ELSE 0 END) AS abn_k_rate,
      AVG(CASE WHEN l.label = 'platelet count' AND l.is_abnormal = 1 THEN 1 ELSE 0 END) AS abn_platelets_rate,
      AVG(CASE WHEN l.label = 'hemoglobin' AND l.is_abnormal = 1 THEN 1 ELSE 0 END) AS abn_hgb_rate,
      AVG(CASE WHEN l.label = 'wbc count' AND l.is_abnormal = 1 THEN 1 ELSE 0 END) AS abn_wbc_rate
    FROM cohort c
    LEFT JOIN labs_72h l ON c.hadm_id = l.hadm_id
    GROUP BY group_type
  )

-- Final output
SELECT * FROM summary_stats;