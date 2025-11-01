WITH cohort AS (
  -- Female patients aged 74-84 with PE (ICD-10 I26%), first PE admission only
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.anchor_age,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
        WHERE i.subject_id = p.subject_id AND i.hadm_id = a.hadm_id
      ) THEN 1 ELSE 0 
    END AS in_icu
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
    AND a.admittime = (
      -- First PE admission per subject to avoid duplicates
      SELECT MIN(a2.admittime) 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2 
      JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a2.hadm_id = d2.hadm_id
      WHERE a2.subject_id = a.subject_id
        AND d2.icd_version = 10
        AND d2.icd_code LIKE 'I26%'
    )
),
meds AS (
  -- Medications in first 24 hours of admission
  SELECT 
    c.*,
    LOWER(pr.drug) AS drug_lower
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
    AND pr.drug IS NOT NULL
),
complexity AS (
  -- Medication complexity (distinct drug count) with flags for QT/bleeding
  SELECT 
    hadm_id,
    COUNT(DISTINCT drug_lower) AS med_count,
    MAX(CASE WHEN drug_lower LIKE '%amiodarone%' OR drug_lower LIKE '%sotalol%' OR drug_lower LIKE '%haloperidol%' 
                  OR drug_lower LIKE '%methadone%' OR drug_lower LIKE '%ondansetron%' 
             THEN 1 ELSE 0 END) AS has_qt,
    MAX(CASE WHEN drug_lower LIKE '%aspirin%' OR drug_lower LIKE '%clopidogrel%' OR drug_lower LIKE '%warfarin%' 
                  OR drug_lower LIKE '%heparin%' OR drug_lower LIKE '%enoxaparin%'
             THEN 1 ELSE 0 END) AS has_bleeding_risk
  FROM meds
  GROUP BY hadm_id
),
complexity_with_percentile AS (
  SELECT 
    *,
    PERCENT_RANK() OVER (ORDER BY med_count) AS complexity_percentile
  FROM complexity
),
los_stats AS (
  -- LOS in days
  SELECT 
    c.hadm_id,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    c.in_icu,
    COALESCE(x.med_count, 0) AS med_count,  -- Handle no meds
    COALESCE(x.has_qt, 0) AS has_qt,
    COALESCE(x.has_bleeding_risk, 0) AS has_bleeding_risk,
    COALESCE(x.complexity_percentile, 0) AS complexity_percentile,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN complexity_with_percentile x ON c.hadm_id = x.hadm_id
),
q75_cte AS (
  SELECT APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q75_los
  FROM los_stats
)
-- Final aggregates: distribution, prevalence, percentiles, ICU comparison, top-quartile LOS/mortality
SELECT 
  in_icu,
  COUNT(*) AS n_patients,
  -- Medication complexity distribution
  AVG(med_count) AS mean_complexity,
  MIN(med_count) AS min_complexity,
  MAX(med_count) AS max_complexity,
  STDDEV(med_count) AS sd_complexity,
  -- Prevalence (% with at least one)
  AVG(has_qt) * 100 AS pct_qt_prolonging,
  AVG(has_bleeding_risk) * 100 AS pct_bleeding_risk,
  -- Mean complexity percentile
  AVG(complexity_percentile) * 100 AS mean_complexity_percentile,
  -- LOS and mortality overall
  AVG(los_days) AS mean_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  -- Top-quartile LOS: compute Q75, then % above it and mortality for those
  (SELECT q75_los FROM q75_cte) AS q75_los,
  AVG(CASE WHEN los_days > (SELECT q75_los FROM q75_cte) THEN 1.0 ELSE 0 END) * 100 AS pct_top_quartile_los,
  SAFE_DIVIDE(
    SUM(CASE WHEN los_days > (SELECT q75_los FROM q75_cte) THEN hospital_expire_flag ELSE 0 END) * 100.0,
    SUM(CASE WHEN los_days > (SELECT q75_los FROM q75_cte) THEN 1 ELSE 0 END)
  ) AS top_quartile_mortality_pct
FROM los_stats
GROUP BY in_icu
ORDER BY in_icu;