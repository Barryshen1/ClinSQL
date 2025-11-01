WITH cohort AS (
  -- Base cohort: males 48-58 with primary pneumonia diagnosis (ICD-10 J12-J18*)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    i.stay_id,
    i.intime AS icu_intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.icd_version = '10'
    AND d.seq_num = 1
    AND d.icd_code LIKE 'J1[2-8]%'
),

med_admin AS (
  -- Meds in first 24h (using hospital prescriptions for all inpatients)
  SELECT DISTINCT 
    c.subject_id,
    c.hadm_id,
    pr.drug
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE TIMESTAMP(pr.starttime) <= TIMESTAMP(c.admittime) + INTERVAL 24 HOUR
    AND pr.status IN ('Allow', 'Completed')  -- Active orders only
    AND (pr.drug LIKE '%antibiotic%' OR pr.drug NOT LIKE '%antibiotic%' )  -- All meds, including antibiotics
),

serotonergic_meds AS (
  -- Flag patients with serotonergic meds in first 24h (common drug names)
  SELECT 
    ma.subject_id,
    ma.hadm_id,
    1 AS serotonergic_risk
  FROM med_admin ma
  WHERE ma.drug LIKE ANY(
    '%Sertraline%', '%Fluoxetine%', '%Paroxetine%', '%Citalopram%', '%Escitalopram%',
    '%Venlafaxine%', '%Duloxetine%', '%Trazodone%', '%Mirtazapine%', '%Amitriptyline%',
    '%Nortriptyline%', '%Sumatriptan%', '%Linezolid%'
  )
  GROUP BY subject_id, hadm_id
),

patient_meds AS (
  -- Med complexity: distinct meds per patient (only those with >=1 med)
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT ma.drug) AS med_count
  FROM cohort c
  INNER JOIN med_admin ma 
    ON c.hadm_id = ma.hadm_id
  GROUP BY c.hadm_id
  HAVING med_count >= 1
),

los_stats AS (
  -- Base LOS and mortality
  SELECT 
    c.hadm_id,
    DATETIME_DIFF(PARSE_DATETIME('%Y-%m-%d %H:%M:%S', c.dischtime), 
                  PARSE_DATETIME('%Y-%m-%d %H:%M:%S', c.admittime), DAY) AS los_days,
    CASE WHEN c.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality
  FROM cohort c
),

full_cohort AS (
  SELECT 
    ls.*,
    COALESCE(sm.serotonergic_risk, 0) AS serotonergic_risk,
    CASE WHEN c.icu_intime IS NOT NULL THEN 1 ELSE 0 END AS is_icu
  FROM los_stats ls
  INNER JOIN cohort c ON ls.hadm_id = c.hadm_id  -- Ensure join
  LEFT JOIN serotonergic_meds sm ON ls.hadm_id = sm.hadm_id
),

q75_los AS (
  SELECT 
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q75_los
  FROM full_cohort
),

top_quartile AS (
  SELECT 
    fc.*
  FROM full_cohort fc
  CROSS JOIN q75_los ql
  WHERE fc.los_days >= ql.q75_los
)

-- Medication complexity distribution (for patients using meds)
SELECT 
  'Medication Complexity' AS metric,
  AVG(med_count) AS mean_complexity,
  APPROX_QUANTILES(med_count, 4)[OFFSET(1)] AS p25_complexity,
  APPROX_QUANTILES(med_count, 4)[OFFSET(2)] AS p50_complexity,
  APPROX_QUANTILES(med_count, 4)[OFFSET(3)] AS p75_complexity
FROM patient_meds

UNION ALL

-- LOS and mortality comparison: serotonergic risk vs overall, for all and ICU
SELECT 
  CONCAT('LOS_', CASE WHEN fc.is_icu = 1 THEN 'ICU_' ELSE '' END, 'Serotonergic_', fc.serotonergic_risk) AS metric,
  AVG(fc.los_days) AS mean_los,
  NULL AS p25_complexity,
  NULL AS p50_complexity,
  NULL AS p75_complexity
FROM full_cohort fc
GROUP BY fc.is_icu, fc.serotonergic_risk

UNION ALL

SELECT 
  CONCAT('Mortality_', CASE WHEN fc.is_icu = 1 THEN 'ICU_' ELSE '' END, 'Serotonergic_', fc.serotonergic_risk) AS metric,
  AVG(CAST(fc.mortality AS FLOAT)) * 100 AS mean_mortality_pct,
  NULL AS p25_complexity,
  NULL AS p50_complexity,
  NULL AS p75_complexity
FROM full_cohort fc
GROUP BY fc.is_icu, fc.serotonergic_risk

UNION ALL

-- Top-quartile LOS and mortality
SELECT 
  CONCAT('TopQ_LOS_', CASE WHEN tq.is_icu = 1 THEN 'ICU_' ELSE '' END, 'Serotonergic_', tq.serotonergic_risk) AS metric,
  AVG(tq.los_days) AS mean_los,
  NULL AS p25_complexity,
  NULL AS p50_complexity,
  NULL AS p75_complexity
FROM top_quartile tq
GROUP BY tq.is_icu, tq.serotonergic_risk

UNION ALL

SELECT 
  CONCAT('TopQ_Mortality_', CASE WHEN tq.is_icu = 1 THEN 'ICU_' ELSE '' END, 'Serotonergic_', tq.serotonergic_risk) AS metric,
  AVG(CAST(tq.mortality AS FLOAT)) * 100 AS mean_mortality_pct,
  NULL AS p25_complexity,
  NULL AS p50_complexity,
  NULL AS p75_complexity
FROM top_quartile tq
GROUP BY tq.is_icu, tq.serotonergic_risk

ORDER BY metric;