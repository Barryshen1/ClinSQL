WITH cohort AS (
  -- Base cohort: females aged 68-78 with inpatient admissions
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 68 AND 78
    AND p.gender = 'F'
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
    AND a.hadm_id IS NOT NULL
),

trauma_cohort AS (
  -- Filter for multi-trauma: >=2 distinct injury categories (corrected ICD-10 injury ranges)
  SELECT 
    c.*,
    COUNT(DISTINCT CASE 
      WHEN d.icd_version = 'ICD-10' AND REGEXP_CONTAINS(d.icd_code, r'^S0[0-9]') THEN 1
      WHEN d.icd_version = 'ICD-10' AND REGEXP_CONTAINS(d.icd_code, r'^S1[0-9]') THEN 1
      WHEN d.icd_version = 'ICD-10' AND REGEXP_CONTAINS(d.icd_code, r'^S[2-9][0-9]') THEN 1
      WHEN d.icd_version = 'ICD-10' AND REGEXP_CONTAINS(d.icd_code, r'^T[0-8][0-9]') THEN 1
      ELSE NULL 
    END) AS injury_category_count
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  WHERE c.rn = 1  -- First admission
    AND d.icd_version = 'ICD-10'
    AND (d.icd_code LIKE 'S%' OR d.icd_code LIKE 'T%')  -- Injury/trauma codes
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, c.anchor_age, c.rn
  HAVING injury_category_count >= 2  -- Multi-trauma
),

serotonergic_drugs AS (
  -- Flag admissions with serotonergic interaction risk (>=2 distinct serotonergic drugs in first 24h)
  SELECT 
    tc.subject_id,
    tc.hadm_id,
    COUNT(DISTINCT CASE 
      WHEN LOWER(pr.drug) LIKE '%sertraline%' OR
           LOWER(pr.drug) LIKE '%fluoxetine%' OR
           LOWER(pr.drug) LIKE '%citalopram%' OR
           LOWER(pr.drug) LIKE '%escitalopram%' OR
           LOWER(pr.drug) LIKE '%paroxetine%' OR
           LOWER(pr.drug) LIKE '%venlafaxine%' OR
           LOWER(pr.drug) LIKE '%duloxetine%' OR
           LOWER(pr.drug) LIKE '%mirtazapine%' OR
           LOWER(pr.drug) LIKE '%trazodone%' OR
           LOWER(pr.drug) LIKE '%fentanyl%' OR
           LOWER(pr.drug) LIKE '%morphine%' OR
           LOWER(pr.drug) LIKE '%meperidine%' OR
           LOWER(pr.drug) LIKE '%tramadol%'
      THEN pr.drug 
      ELSE NULL 
    END) AS serotonergic_count
  FROM trauma_cohort tc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON tc.subject_id = pr.subject_id AND tc.hadm_id = pr.hadm_id
    AND pr.starttime >= tc.admittime
    AND pr.starttime < tc.admittime + INTERVAL 1 DAY
  GROUP BY tc.subject_id, tc.hadm_id
),

complexity AS (
  -- First-24h medication complexity (distinct drugs), with group-specific percentile
  SELECT 
    sd.subject_id,
    sd.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_complexity,
    CASE WHEN sd.serotonergic_count >= 2 THEN 1 ELSE 0 END AS has_risk,
    PERCENT_RANK() OVER (PARTITION BY CASE WHEN sd.serotonergic_count >= 2 THEN 1 ELSE 0 END ORDER BY COUNT(DISTINCT pr.drug)) AS complexity_percentile,
    tc.admittime,
    tc.dischtime
  FROM serotonergic_drugs sd
  INNER JOIN trauma_cohort tc
    ON sd.subject_id = tc.subject_id AND sd.hadm_id = tc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON sd.subject_id = pr.subject_id 
    AND sd.hadm_id = pr.hadm_id
    AND pr.starttime >= tc.admittime
    AND pr.starttime < tc.admittime + INTERVAL 1 DAY
  GROUP BY sd.subject_id, sd.hadm_id, sd.serotonergic_count, tc.admittime, tc.dischtime
),

los_mort AS (
  -- LOS and mortality
  SELECT 
    c.subject_id,
    c.hadm_id,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    c.hospital_expire_flag
  FROM trauma_cohort c
),

final_cohort AS (
  -- Combine with LOS/mortality
  SELECT 
    comp.*,
    lm.los_days,
    lm.hospital_expire_flag
  FROM complexity comp
  INNER JOIN los_mort lm
    ON comp.subject_id = lm.subject_id AND comp.hadm_id = lm.hadm_id
),

-- Aggregated stats with quartiles (using BigQuery syntax)
agg_stats AS (
  SELECT 
    CASE WHEN fc.has_risk = 1 THEN 'With Serotonergic Risk' ELSE 'Without Serotonergic Risk' END AS risk_group,
    COUNT(*) AS n_patients,
    MIN(fc.med_complexity) AS min_complexity,
    MAX(fc.med_complexity) AS max_complexity,
    -- Approx quartiles using APPROX_QUANTILES (returns array; extract Q1=offset 0, Q3=offset 2)
    (SELECT q[OFFSET(0)] FROM UNNEST(APPROX_QUANTILES(fc.med_complexity, 4)) AS q) AS q1_complexity,
    (SELECT q[OFFSET(1)] FROM UNNEST(APPROX_QUANTILES(fc.med_complexity, 4)) AS q) AS q2_complexity,
    (SELECT q[OFFSET(2)] FROM UNNEST(APPROX_QUANTILES(fc.med_complexity, 4)) AS q) AS q3_complexity,
    AVG(fc.complexity_percentile) * 100 AS avg_complexity_percentile,
    AVG(fc.los_days) AS avg_los,
    AVG(fc.hospital_expire_flag) * 100 AS mortality_rate_pct,
    -- For top quartile filter later
    fc.med_complexity,
    fc.complexity_percentile,
    fc.los_days,
    fc.hospital_expire_flag
  FROM final_cohort fc
  GROUP BY fc.has_risk
)

-- Main results: quartiles, avg percentile, LOS, mortality by risk group
SELECT 
  risk_group,
  n_patients,
  min_complexity,
  q1_complexity AS q1_25,
  q2_complexity AS q1_50,
  q3_complexity AS q1_75,
  max_complexity,
  avg_complexity_percentile,
  avg_los,
  mortality_rate_pct
FROM agg_stats

UNION ALL

-- LOS/mortality for top quartile (entire cohort, percentile >0.75)
SELECT 
  'Top Complexity Quartile (All)' AS risk_group,
  COUNT(*) AS n_patients,
  NULL AS min_complexity,
  NULL AS q1_25,
  NULL AS q1_50,
  NULL AS q1_75,
  NULL AS max_complexity,
  NULL AS avg_complexity_percentile,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_pct
FROM agg_stats
WHERE complexity_percentile > 0.75;