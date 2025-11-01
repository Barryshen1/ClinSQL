WITH cohort AS (
  -- Base cohort: males aged 78-88 with ICU stays
  SELECT 
    p.subject_id,
    p.anchor_age,
    MIN(i.intime) AS first_intime,  -- First ICU stay per patient
    MIN(a.hadm_id) AS first_hadm_id,
    a.hospital_expire_flag,
    BOOL_OR(CASE WHEN d.icd_version = '10' AND d.icd_code IN ('E11.00') THEN TRUE ELSE FALSE END) AS has_hhs
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND i.los > 0
  GROUP BY p.subject_id, p.anchor_age, a.hospital_expire_flag
),

vitals AS (
  -- Vital signs in first 48h; hardcoded common itemids from d_items (Routine Vital Signs)
  SELECT 
    c.subject_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum,
    di.label,
    di.lownormalvalue AS low_norm,
    di.highnormalvalue AS high_norm
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON c.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.subject_id = i.subject_id AND c.stay_id = i.stay_id
  INNER JOIN cohort coh ON c.subject_id = coh.subject_id AND i.intime = coh.first_intime
  WHERE c.charttime >= i.intime
    AND c.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
    AND c.valuenum IS NOT NULL
    AND di.category = 'Routine Vital Signs'
    AND c.itemid IN (220045, 220179, 220180, 220210, 223761, 220277, 223900, 223901, 223902)  -- HR, SBP, DBP, RR, Temp, SpO2, GCS components
    -- Artifact filter example (customize per vital)
    AND NOT (c.itemid = 220045 AND (c.valuenum < 30 OR c.valuenum > 250))  -- HR bounds
    -- Add similar for others if needed
),

normal_ranges AS (
  -- Fallback normals if d_items NULL (clinical defaults)
  SELECT 
    itemid,
    label,
    COALESCE(low_norm, CASE itemid 
      WHEN 220045 THEN 60 WHEN 220179 THEN 90 WHEN 220180 THEN 60 
      WHEN 220210 THEN 12 WHEN 223761 THEN 36 WHEN 220277 THEN 92 
      WHEN 223900 THEN 1 WHEN 223901 THEN 1 WHEN 223902 THEN 1 ELSE NULL END) AS low_norm,
    COALESCE(high_norm, CASE itemid 
      WHEN 220045 THEN 100 WHEN 220179 THEN 140 WHEN 220180 THEN 90 
      WHEN 220210 THEN 30 WHEN 223761 THEN 38 WHEN 220277 THEN 100 
      WHEN 223900 THEN 6 WHEN 223901 THEN 5 WHEN 223902 THEN 6 ELSE NULL END) AS high_norm,
    -- Fixed SD for z-score (approximate)
    CASE itemid WHEN 220045 THEN 15 WHEN 220179 THEN 20 WHEN 220180 THEN 10 
                WHEN 220210 THEN 5 WHEN 223761 THEN 0.5 WHEN 220277 THEN 3 
                WHEN 223900 THEN 1 WHEN 223901 THEN 1 WHEN 223902 THEN 1 ELSE 1 END AS sd_norm
  FROM vitals
  GROUP BY itemid, label, low_norm, high_norm  -- Unique per item
),

abnormal_burden AS (
  -- Compute per patient: mean abnormal fraction across vitals
  SELECT 
    v.subject_id,
    AVG(  -- Mean burden across vitals
      SAFE_DIVIDE(
        COUNTIF(v.valuenum < nr.low_norm OR v.valuenum > nr.high_norm),  -- Abnormal count
        COUNT(*)  -- Total count per vital
      )
    ) AS mean_abnormal_burden
  FROM vitals v
  INNER JOIN normal_ranges nr ON v.itemid = nr.itemid
  GROUP BY v.subject_id
  HAVING COUNT(*) > 0  -- Patients with vitals data
),

instability_score AS (
  -- Composite: mean |z-score| across all observations/vitals (absolute for instability)
  SELECT 
    v.subject_id,
    AVG(
      ABS(  -- Absolute deviation
        SAFE_DIVIDE(
          (v.valuenum - (nr.low_norm + nr.high_norm)/2),  -- Deviation from mid-normal
          nr.sd_norm
        )
      )
    ) AS mean_instability_score
  FROM vitals v
  INNER JOIN normal_ranges nr ON v.itemid = nr.itemid
  WHERE nr.low_norm IS NOT NULL AND nr.high_norm IS NOT NULL AND nr.sd_norm > 0
  GROUP BY v.subject_id
  HAVING COUNT(*) > 0
),

los_data AS (
  -- ICU LOS (first stay)
  SELECT 
    i.subject_id,
    i.los AS los_days  -- Already in days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN cohort c ON i.subject_id = c.subject_id
  WHERE i.intime = c.first_intime
),

aggregated_metrics AS (
  -- Combine and group by HHS vs Control
  SELECT 
    CASE WHEN c.has_hhs THEN 'HHS' ELSE 'Control' END AS patient_group,
    ab.mean_abnormal_burden,
    ins.mean_instability_score,
    l.los_days,
    c.hospital_expire_flag AS mortality_flag
  FROM cohort c
  LEFT JOIN abnormal_burden ab ON c.subject_id = ab.subject_id
  LEFT JOIN instability_score ins ON c.subject_id = ins.subject_id
  LEFT JOIN los_data l ON c.subject_id = l.subject_id
  WHERE ab.mean_abnormal_burden IS NOT NULL  -- Require vitals data
)

-- Final percentiles and means
SELECT 
  patient_group,
  'Composite Instability Score' AS metric,
  PERCENTILE_CONT(0.25) OVER (PARTITION BY patient_group ORDER BY mean_instability_score) AS p25,
  PERCENTILE_CONT(0.50) OVER (PARTITION BY patient_group ORDER BY mean_instability_score) AS median,
  PERCENTILE_CONT(0.75) OVER (PARTITION BY patient_group ORDER BY mean_instability_score) AS p75
FROM aggregated_metrics

UNION ALL

SELECT 
  patient_group,
  'Mean Abnormal-Vital Burden' AS metric,
  PERCENTILE_CONT(0.25) OVER (PARTITION BY patient_group ORDER BY mean_abnormal_burden) AS p25,
  PERCENTILE_CONT(0.50) OVER (PARTITION BY patient_group ORDER BY mean_abnormal_burden) AS median,
  PERCENTILE_CONT(0.75) OVER (PARTITION BY patient_group ORDER BY mean_abnormal_burden) AS p75
FROM aggregated_metrics

UNION ALL

SELECT 
  patient_group,
  'Mean ICU LOS (days)' AS metric,
  PERCENTILE_CONT(0.25) OVER (PARTITION BY patient_group ORDER BY los_days) AS p25,
  PERCENTILE_CONT(0.50) OVER (PARTITION BY patient_group ORDER BY los_days) AS median,
  PERCENTILE_CONT(0.75) OVER (PARTITION BY patient_group ORDER BY los_days) AS p75
FROM aggregated_metrics

UNION ALL

SELECT 
  patient_group,
  'Mortality (%)' AS metric,
  NULL AS p25,
  ROUND(AVG(mortality_flag) * 100, 2) AS median,  -- Proportion as %
  NULL AS p75
FROM aggregated_metrics
GROUP BY patient_group

ORDER BY patient_group, metric;