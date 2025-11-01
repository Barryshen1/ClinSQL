WITH base_cohort AS (
  -- Female inpatients aged 44-54, first admission per subject
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admission_type != 'OBSERVATION'
    AND a.dischtime > a.admittime  -- Valid LOS
),
ich_cohort AS (
  -- Flag ICH and major complications, join patients for dod
  SELECT 
    bc.*,
    p.dod,
    MAX(CASE 
      WHEN (di.icd_version = 'ICD-10' AND di.icd_code LIKE 'I61%') 
        OR (di.icd_version = 'ICD-9' AND di.icd_code IN ('430', '431')) 
      THEN 1 ELSE 0 
    END) AS has_ich,
    MAX(CASE 
      WHEN di.seq_num > 1 
        AND ((di.icd_version = 'ICD-10' AND (di.icd_code LIKE 'J12%' OR di.icd_code LIKE 'J13%' OR di.icd_code LIKE 'J14%' 
                                             OR di.icd_code LIKE 'J15%' OR di.icd_code LIKE 'J16%' OR di.icd_code LIKE 'J17%' 
                                             OR di.icd_code LIKE 'J18%'  -- Pneumonia
                                             OR di.icd_code = 'I26' OR di.icd_code = 'I82'  -- PE/DVT
                                             OR di.icd_code = 'N17'  -- AKI
                                             OR di.icd_code = 'A41'))  -- Sepsis
             OR (di.icd_version = 'ICD-9' AND (di.icd_code LIKE '48[0-6]%'  -- Pneumonia approx
                                               OR di.icd_code IN ('4151', '453')  -- PE/DVT approx
                                               OR di.icd_code = '584'  -- AKI approx
                                               OR di.icd_code LIKE '038%' OR di.icd_code = '99591')))  -- Sepsis approx
      THEN 1 ELSE 0 
    END) AS has_major_comp
  FROM base_cohort bc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON bc.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON bc.subject_id = di.subject_id AND bc.hadm_id = di.hadm_id
  WHERE bc.rn = 1  -- First admission only
  GROUP BY bc.subject_id, bc.anchor_age, bc.hadm_id, bc.admittime, bc.dischtime, 
           bc.hospital_expire_flag, bc.rn, p.dod
),
outcomes AS (
  -- Compute outcomes and proxy risk score
  SELECT 
    has_ich,
    -- 90-day mortality
    AVG(CASE 
      WHEN p.dod IS NOT NULL 
        AND DATE_DIFF(SAFE_CAST(p.dod AS DATE), SAFE_CAST(admittime AS DATE), DAY) <= 90 
        AND DATE(SAFE_CAST(p.dod AS DATE)) >= DATE(SAFE_CAST(admittime AS DATE))
      THEN 1.0 ELSE 0.0 
    END) AS mortality_90d_rate,
    -- Major complication rate
    AVG(has_major_comp) AS major_comp_rate,
    -- Survivor LOS median/IQR (days, non-decedents)
    PERCENTILE_CONT(0.5, COUNTIF(hospital_expire_flag = 0)) 
      OVER (PARTITION BY has_ich ORDER BY DATE_DIFF(SAFE_CAST(dischtime AS DATE), SAFE_CAST(admittime AS DATE), DAY) 
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS survivor_los_median,
    APPROX_QUANTILES(
      CASE WHEN hospital_expire_flag = 0 
           THEN DATE_DIFF(SAFE_CAST(dischtime AS DATE), SAFE_CAST(admittime AS DATE), DAY) 
           ELSE NULL END, 4 IGNORE NULLS)[OFFSET(1)] AS survivor_los_q1,
    APPROX_QUANTILES(
      CASE WHEN hospital_expire_flag = 0 
           THEN DATE_DIFF(SAFE_CAST(dischtime AS DATE), SAFE_CAST(admittime AS DATE), DAY) 
           ELSE NULL END, 4 IGNORE NULLS)[OFFSET(3)] AS survivor_los_q3,
    -- Proxy risk score: age + 10*mortality_flag + 5*comp (median/IQR)
    PERCENTILE_CONT(0.5, COUNT(*)) 
      OVER (PARTITION BY has_ich ORDER BY anchor_age + 10 * hospital_expire_flag + 5 * has_major_comp 
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS risk_score_median,
    APPROX_QUANTILES(anchor_age + 10 * hospital_expire_flag + 5 * has_major_comp, 4 IGNORE NULLS)[OFFSET(1)] AS risk_score_q1,
    APPROX_QUANTILES(anchor_age + 10 * hospital_expire_flag + 5 * has_major_comp, 4 IGNORE NULLS)[OFFSET(3)] AS risk_score_q3
  FROM ich_cohort
  GROUP BY has_ich
),
ich_risk_dist AS (
  -- Risk proxy distribution for ICH cohort (for percentile)
  SELECT 
    anchor_age + 10 * hospital_expire_flag + 5 * has_major_comp AS risk_proxy
  FROM ich_cohort
  WHERE has_ich = 1
),
index_percentile AS (
  -- Percentile for 49yo F with ICH (risk_proxy=49, assuming alive no comp)
  SELECT 
    APPROX_PERCENTILE(risk_proxy, 0.5, COUNT(*) OVER ()) AS matched_risk_percentile  -- Median of dist <=49, but approx as percentile of 49
  FROM ich_risk_dist
  WHERE risk_proxy <= 49
  LIMIT 1  -- For the value at/near 49th percentile
)
SELECT 
  -- ICH cohort metrics
  'ICH' AS cohort,
  o1.mortality_90d_rate,
  o1.risk_score_median,
  o1.risk_score_q1 AS risk_score_iqr_lower,
  o1.risk_score_q3 AS risk_score_iqr_upper,
  o1.major_comp_rate AS ich_major_comp_rate,
  o1.survivor_los_median AS ich_survivor_los_median,
  o1.survivor_los_q1 AS ich_los_iqr_lower,
  o1.survivor_los_q3 AS ich_los_iqr_upper,
  -- Non-ICH comparison
  o2.mortality_90d_rate AS non_ich_mortality_90d,
  o2.major_comp_rate AS non_ich_major_comp_rate,
  o2.survivor_los_median AS non_ich_survivor_los_median,
  -- Matched risk percentile for index case
  ip.matched_risk_percentile
FROM outcomes o1
LEFT JOIN outcomes o2 ON o1.has_ich = 1 AND o2.has_ich = 0
CROSS JOIN index_percentile ip
WHERE o1.has_ich = 1;