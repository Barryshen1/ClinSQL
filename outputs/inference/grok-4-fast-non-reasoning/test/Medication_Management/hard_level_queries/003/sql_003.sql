WITH cohort AS (
  -- Base cohort: males 39-49, inpatient admissions (survivors only for LOS focus)
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.hospital_expire_flag = 0  -- Focus on discharged alive for LOS/mortality comparison
),

med_exposures AS (
  -- Medications in first 24h: use prescriptions (hospital-wide proxy for administered)
  SELECT 
    c.hadm_id,
    pres.drug AS med_name,
    -- Hardcoded itemid-like filter via drug name (in practice, join d_items for itemid)
    CASE 
      WHEN LOWER(pres.drug) IN ('amiodarone', 'haloperidol', 'ondansetron', 'methadone', 'levofloxacin') THEN 1 
      ELSE 0 
    END AS is_qt_prolonging,
    CASE 
      WHEN LOWER(pres.drug) IN ('heparin', 'warfarin', 'enoxaparin', 'aspirin', 'clopidogrel') THEN 1 
      ELSE 0 
    END AS is_bleeding_risk
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON c.hadm_id = pres.hadm_id
  WHERE 
    pres.starttime >= c.admittime
    AND pres.starttime < TIMESTAMP_ADD(TIMESTAMP(c.admittime), INTERVAL 24 HOUR)
    AND pres.drug IS NOT NULL
    AND TRIM(pres.drug) != ''
),

complexity AS (
  -- Calculate unique meds count and flags per admission, then percentiles
  SELECT 
    subject_id,
    hadm_id,
    anchor_age,
    admittime,
    dischtime,
    hospital_expire_flag,
    los_days,
    med_complexity,
    has_qt_exposure,
    has_bleeding_exposure,
    SAFE_CAST(complexity_percentile AS FLOAT64) AS complexity_percentile,
    complexity_quartile
  FROM (
    SELECT 
      c.*,
      COUNT(DISTINCT me.med_name) AS med_complexity,
      MAX(me.is_qt_prolonging) AS has_qt_exposure,
      MAX(me.is_bleeding_risk) AS has_bleeding_exposure,
      -- Percentile rank of complexity over all cohort
      PERCENT_RANK() OVER (ORDER BY COUNT(DISTINCT me.med_name)) AS complexity_percentile,
      NTILE(4) OVER (ORDER BY COUNT(DISTINCT me.med_name) DESC) AS complexity_quartile
    FROM 
      cohort c
    LEFT JOIN 
      med_exposures me
      ON c.hadm_id = me.hadm_id
    GROUP BY 
      c.subject_id, c.hadm_id, c.anchor_age, c.admittime, c.dischtime, c.hospital_expire_flag, c.los_days
  ) sub
),

grouped_stats AS (
  -- Group: 1=QT, 2=Bleeding, 0=Neither
  SELECT 
    CASE 
      WHEN has_qt_exposure = 1 AND has_bleeding_exposure = 0 THEN 'QT-prolonging'
      WHEN has_bleeding_exposure = 1 AND has_qt_exposure = 0 THEN 'Bleeding-risk'
      ELSE 'General'
    END AS group_type,
    -- Complexity: mean/median count and avg percentile
    AVG(med_complexity) AS avg_complexity,
    APPROX_QUANTILES(med_complexity, 2)[OFFSET(1)] AS median_complexity,  -- BigQuery approx median
    AVG(complexity_percentile) * 100 AS avg_percentile_rank,
    -- LOS and mortality
    AVG(los_days) AS avg_los,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate_pct,
    COUNT(*) AS n_patients
  FROM 
    complexity
  GROUP BY 
    1
),

top_quartile AS (
  -- Top quartile (highest complexity)
  SELECT 
    'Top Complexity Quartile' AS group_type,
    NULL AS avg_complexity,
    NULL AS median_complexity,
    NULL AS avg_percentile_rank,
    AVG(los_days) AS avg_los,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate_pct,
    COUNT(*) AS n_patients
  FROM 
    complexity
  WHERE 
    complexity_quartile = 1  -- Top 25%
)

-- Combine comparisons and target report
SELECT * FROM grouped_stats
UNION ALL
SELECT * FROM top_quartile
ORDER BY 
  CASE group_type 
    WHEN 'QT-prolonging' THEN 1
    WHEN 'Bleeding-risk' THEN 2
    WHEN 'General' THEN 3
    WHEN 'Top Complexity Quartile' THEN 4
  END;