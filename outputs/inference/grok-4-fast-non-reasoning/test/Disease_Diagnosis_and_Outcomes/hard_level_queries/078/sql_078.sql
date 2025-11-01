WITH cohort AS (
  -- Base cohort: females aged 59-69 with HF admission
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    SAFE_CAST(a.hospital_expire_flag AS INT64) AS hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND EXTRACT(YEAR FROM a.admittime) >= p.anchor_year
    AND (
      (d.icd_version = '10' AND d.icd_code LIKE 'I50%') OR
      (d.icd_version = '9' AND d.icd_code LIKE '428%')
    )
),

aki_max AS (
  -- Compute max creatinine per admission
  SELECT 
    subject_id,
    hadm_id,
    MAX(LEAST(valuenum, 100)) AS max_creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort c
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  WHERE l.itemid IN (50912, 50983, 51006)  -- Creatinine items
    AND l.charttime >= c.admittime 
    AND l.charttime <= COALESCE(c.dischtime, DATE_SUB(c.admittime, INTERVAL 1 SECOND))
    AND l.valuenum IS NOT NULL
  GROUP BY subject_id, hadm_id
),

aki_cohort AS (
  -- AKI proxy: max creatinine > 4.0 mg/dL during admission
  SELECT 
    c.*,
    (SAFE_CAST(COALESCE(am.max_creatinine, 0) AS FLOAT64) > 4.0) AS aki_flag
  FROM cohort c
  LEFT JOIN aki_max am
    ON c.subject_id = am.subject_id AND c.hadm_id = am.hadm_id
),

ards_cohort AS (
  -- ARDS from diagnoses
  SELECT 
    ac.*,
    MAX(CASE 
      WHEN d.icd_version = '10' AND d.icd_code ILIKE 'J80' THEN 1
      WHEN d.icd_version = '9' AND d.icd_code IN ('5185', '51882') THEN 1
      ELSE 0 
    END) AS ards_flag
  FROM aki_cohort ac
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ac.subject_id = d.subject_id 
    AND ac.hadm_id = d.hadm_id
  GROUP BY 
    ac.subject_id, ac.hadm_id, ac.admittime, ac.dischtime, ac.deathtime, 
    ac.hospital_expire_flag, ac.aki_flag
),

outcomes AS (
  SELECT 
    *,
    -- Survival time in hours for deaths
    CASE WHEN hospital_expire_flag = 1 AND deathtime IS NOT NULL 
         THEN TIMESTAMP_DIFF(deathtime, admittime, HOUR)
         ELSE NULL 
    END AS survival_hours,
    -- Composite score: sum of binary risks
    (CAST(COALESCE(aki_flag, FALSE) AS INT64) + hospital_expire_flag + CAST(COALESCE(ards_flag, 0) AS INT64)) AS composite_score
  FROM ards_cohort
)

SELECT 
  -- Rates
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(CASE WHEN aki_flag THEN 1.0 ELSE 0 END) AS aki_rate,
  AVG(CASE WHEN ards_flag = 1 THEN 1.0 ELSE 0 END) AS ards_rate,
  
  -- Median survival among deaths (NULL if no deaths)
  (SELECT APPROX_QUANTILES(survival_hours, 2)[OFFSET(1)] 
   FROM outcomes o2 WHERE o2.survival_hours IS NOT NULL) AS median_survival_hours_deaths,
  
  -- Composite score distribution
  MIN(composite_score) AS composite_min,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(1)] AS composite_p25,
  APPROX_QUANTILES(composite_score, 2)[OFFSET(1)] AS composite_median,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] AS composite_p75,
  APPROX_QUANTILES(composite_score, 10)[OFFSET(9)] AS composite_p90,
  MAX(composite_score) AS composite_max,
  
  -- Cohort size for reference
  COUNT(*) AS cohort_size

FROM outcomes;