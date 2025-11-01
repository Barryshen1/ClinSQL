WITH cohort AS (
  -- Base cohort: males 64-74, inpatient admissions
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    p.dod,
    a.admission_type
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
),

upper_gi_bleed AS (
  -- Filter to admissions with upper GI bleeding (K25/K26)
  SELECT 
    c.*,
    d.icd_code
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  WHERE d.icd_version = 10
    AND (d.icd_code LIKE 'K25%' OR d.icd_code LIKE 'K26%')
),

risk_scores AS (
  -- Compute diagnosis count and major complications per admission
  SELECT 
    u.*,
    COUNT(DISTINCT d_all.icd_code) AS dx_count,
    COUNT(DISTINCT CASE 
      WHEN d_all.icd_code IN (
        -- Curated major complications (ICD-10): sepsis, shock, ARDS, AKI, etc.
        'A41', 'R57', 'J96.0', 'N17', 'K92.2', 'I95.1', 'D65', 'T81.4', 'Y83.9'
        -- Add more as needed: e.g., 'J15.2' (pneumonia), 'I21' (MI), etc.
      ) THEN d_all.icd_code 
    END) AS major_comp_count
  FROM upper_gi_bleed u
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_all
    ON u.hadm_id = d_all.hadm_id
    AND d_all.icd_version = 10
  GROUP BY 
    u.subject_id, u.hadm_id, u.anchor_age, u.admittime, u.dischtime, u.dod, u.admission_type
),

final_cohort AS (
  -- Composite score and quintiles
  SELECT 
    *,
    dx_count + 20 * major_comp_count AS composite_score,
    NTILE(5) OVER (ORDER BY (dx_count + 20 * major_comp_count) ASC) AS quintile,
    -- 30-day mortality flag
    CASE 
      WHEN dod IS NOT NULL 
        AND TIMESTAMP(dod) >= admittime 
        AND TIMESTAMP(dod) <= TIMESTAMP_ADD(admittime, INTERVAL 30 DAY)
      THEN TRUE 
      ELSE FALSE 
    END AS day30_death,
    -- LOS in days (timestamp diff)
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    -- Major comp flag (any)
    CASE WHEN major_comp_count > 0 THEN TRUE ELSE FALSE END AS has_major_comp
  FROM risk_scores
  QUALIFY ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY icd_code) = 1  -- Dedup if multiple GI dx per adm
)

-- Aggregates by quintile
SELECT 
  quintile AS risk_quintile,
  COUNT(*) AS n,
  ROUND(AVG(composite_score), 2) AS mean_score,
  ROUND(AVG(CASE WHEN day30_death THEN 1.0 ELSE 0.0 END) * 100, 2) AS mortality_30d_pct,
  ROUND(AVG(CASE WHEN has_major_comp THEN 1.0 ELSE 0.0 END) * 100, 2) AS major_comp_pct,
  PERCENTILE_CONT(0.5) OVER (ORDER BY los_days) 
    FILTER (WHERE NOT day30_death) AS median_los_survivors
FROM final_cohort
GROUP BY quintile
ORDER BY quintile;