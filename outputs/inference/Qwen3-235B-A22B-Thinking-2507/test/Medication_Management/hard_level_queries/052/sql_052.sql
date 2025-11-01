WITH 
-- Step 1: Build admission cohort with age and HHS diagnosis
admissions_cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    MAX(CASE 
          WHEN d.icd_code IN ('E1001', 'E1101', 'E1301') AND d.icd_version = 10 
          THEN 1 ELSE 0 
        END) OVER (PARTITION BY a.hadm_id) AS has_hhs
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    a.admission_type NOT IN ('OUTPATIENT', 'OBSERVATION')
    AND a.dischtime IS NOT NULL
),

-- Step 2: Define analysis groups
cohort_groups AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    CASE 
      WHEN gender = 'F' AND age_at_admission BETWEEN 68 AND 78 AND has_hhs = 1 
      THEN 'HHS_group' 
      ELSE 'all_inpatients' 
    END AS group_id
  FROM admissions_cohort
),

-- Step 3: Calculate medication complexity and hyperkalemia flags
medication_data AS (
  SELECT 
    c.hadm_id,
    c.group_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    -- Medication complexity: distinct drugs in first 72h
    COUNT(DISTINCT LOWER(p.drug)) AS med_complexity,
    -- Hyperkalemia-risk flag logic
    COUNT(DISTINCT 
      CASE 
        WHEN LOWER(p.drug) IN ('lisinopril', 'enalapril', 'ramipril', 'captopril', 'benazepril', 'fosinopril', 'moexipril', 'perindopril', 'quinapril', 'trandolapril') 
          THEN 'ACE'
        WHEN LOWER(p.drug) IN ('losartan', 'valsartan', 'irbesartan', 'candesartan', 'telmisartan', 'olmesartan', 'eprosartan', 'azilsartan') 
          THEN 'ARB'
        WHEN LOWER(p.drug) IN ('spironolactone', 'amiloride', 'triamterene') 
          THEN 'K_sparing_diuretic'
        WHEN LOWER(p.drug) = 'aliskiren' 
          THEN 'direct_renin_inhibitor'
      END
    ) >= 2 AS has_hyperkalemia_risk
  FROM cohort_groups c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
    AND p.starttime >= c.admittime 
    AND p.starttime < DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY 1, 2, 3, 4, 5
),

-- Step 4: Compute LOS and add hyperkalemia flags
final_cohort AS (
  SELECT 
    group_id,
    med_complexity,
    has_hyperkalemia_risk,
    DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days,
    hospital_expire_flag,
    -- Medication complexity percentile rank within group
    PERCENT_RANK() OVER (
      PARTITION BY group_id 
      ORDER BY med_complexity
    ) * 100 AS complexity_percentile_rank
  FROM medication_data
),
-- NEW: Precompute 75th percentile LOS per group
los_thresholds AS (
  SELECT
    group_id,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS q75_los
  FROM final_cohort
  GROUP BY group_id
)

-- Step 5: Aggregate metrics for both groups with threshold join
SELECT
  fc.group_id,
  -- Medication complexity distribution (25th, 50th, 75th percentiles)
  APPROX_QUANTILES(fc.med_complexity, 100)[OFFSET(25)] AS med_complexity_25,
  APPROX_QUANTILES(fc.med_complexity, 100)[OFFSET(50)] AS med_complexity_50,
  APPROX_QUANTILES(fc.med_complexity, 100)[OFFSET(75)] AS med_complexity_75,
  -- Median percentile rank for hyperkalemia-affected patients
  APPROX_QUANTILES(
    IF(fc.has_hyperkalemia_risk, fc.complexity_percentile_rank, NULL), 
    100
  )[OFFSET(50)] AS median_percentile_rank,
  -- Percent affected by hyperkalemia-risk interactions
  SAFE_DIVIDE(
    COUNTIF(fc.has_hyperkalemia_risk), 
    COUNT(*)
  ) * 100 AS percent_affected,
  -- Top-quartile LOS (75th percentile value) from precomputed threshold
  lt.q75_los AS top_quartile_los,
  -- Mortality rate in top-quartile LOS patients using precomputed threshold
  SAFE_DIVIDE(
    COUNTIF(fc.los_days >= lt.q75_los AND fc.hospital_expire_flag = 1),
    COUNTIF(fc.los_days >= lt.q75_los)
  ) * 100 AS mortality_in_top_quartile
FROM final_cohort fc
INNER JOIN los_thresholds lt
  ON fc.group_id = lt.group_id
GROUP BY fc.group_id, lt.q75_los;