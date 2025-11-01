WITH lab_list AS (
  -- Pick commonly used lab items by name pattern (sodium, potassium, creatinine, WBC, hemoglobin/hematocrit,
  -- platelets, glucose, bilirubin, amylase, lipase). This yields itemids to include from d_labitems.
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%sodium%' OR
    LOWER(label) LIKE '%potassium%' OR
    LOWER(label) LIKE '%creatinine%' OR
    LOWER(label) LIKE '%wbc%' OR
    LOWER(label) LIKE '%white blood%' OR
    LOWER(label) LIKE '%hemoglobin%' OR
    LOWER(label) LIKE '%haemoglobin%' OR
    LOWER(label) LIKE '%hematocrit%' OR
    LOWER(label) LIKE '%platelet%' OR
    LOWER(label) LIKE '%glucose%' OR
    LOWER(label) LIKE '%bilirubin%' OR
    LOWER(label) LIKE '%amylase%' OR
    LOWER(label) LIKE '%lipase%'
),

pancreatitis_adms AS (
  -- Admissions with an ICD diagnosis whose long_title mentions "acute pancreatitis"
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddesc
    ON di.icd_code = ddesc.icd_code
    AND di.icd_version = ddesc.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND LOWER(ddesc.long_title) LIKE '%acute pancreatitis%'
),

-- Compute per-admission lab statistics (total labs, abnormal count, critical flag) in first 48 hours
pancreatitis_lab_stats AS (
  SELECT
    pa.hadm_id,
    pa.subject_id,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag,
    pa.anchor_age,
    -- counts of lab rows with numeric valuenum in the 48h window restricted to our lab_list
    COUNT(CASE WHEN ll.itemid IS NOT NULL AND le.valuenum IS NOT NULL THEN 1 END) AS total_labs,
    -- count of abnormal lab rows (requires numeric valuenum and numeric ref range)
    COUNT(CASE
            WHEN ll.itemid IS NOT NULL
              AND le.valuenum IS NOT NULL
              AND SAFE_CAST(le.ref_range_lower AS FLOAT64) IS NOT NULL
              AND SAFE_CAST(le.ref_range_upper AS FLOAT64) IS NOT NULL
              AND (CAST(le.valuenum AS FLOAT64) < SAFE_CAST(le.ref_range_lower AS FLOAT64)
                   OR CAST(le.valuenum AS FLOAT64) > SAFE_CAST(le.ref_range_upper AS FLOAT64))
            THEN 1
          END) AS abnormal_count,
    -- flag if any critical lab occurred (abnormal and deviates substantially from reference range)
    MAX(CASE
          WHEN ll.itemid IS NOT NULL
            AND le.valuenum IS NOT NULL
            AND SAFE_CAST(le.ref_range_lower AS FLOAT64) IS NOT NULL
            AND SAFE_CAST(le.ref_range_upper AS FLOAT64) IS NOT NULL
            AND (
                 CAST(le.valuenum AS FLOAT64) < (SAFE_CAST(le.ref_range_lower AS FLOAT64) * 0.5)
                 OR CAST(le.valuenum AS FLOAT64) > (SAFE_CAST(le.ref_range_upper AS FLOAT64) * 1.5)
               )
          THEN 1
          ELSE 0
        END) AS critical_flag
  FROM pancreatitis_adms pa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = pa.hadm_id
   AND le.charttime >= pa.admittime
   AND le.charttime < TIMESTAMP_ADD(pa.admittime, INTERVAL 48 HOUR)
  -- join to lab_list to filter to the desired lab itemids without using an IN-subquery in the ON clause
  LEFT JOIN lab_list ll
    ON le.itemid = ll.itemid
  GROUP BY pa.hadm_id, pa.subject_id, pa.admittime, pa.dischtime, pa.hospital_expire_flag, pa.anchor_age
),

-- keep only admissions with at least one lab in first 48 hours and compute instability
pancreatitis_instability AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    anchor_age,
    total_labs,
    abnormal_count,
    critical_flag,
    SAFE_DIVIDE(CAST(abnormal_count AS FLOAT64), NULLIF(CAST(total_labs AS FLOAT64), 0)) AS instability_score,
    -- LOS in days with fractional days
    TIMESTAMP_DIFF(dischtime, admittime, MINUTE) / 1440.0 AS los_days
  FROM pancreatitis_lab_stats
  WHERE total_labs > 0
),

-- assign quintiles across the pancreatitis cohort by instability_score (lowest to highest)
pancreatitis_quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY instability_score ASC) AS instability_quintile
  FROM pancreatitis_instability
),

-- Aggregate statistics per quintile
quintile_aggregates AS (
  SELECT
    instability_quintile,
    COUNT(*) AS n_admissions,
    AVG(instability_score) AS mean_instability,
    AVG(los_days) AS mean_los_days,
    100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_pct,
    100.0 * AVG(CAST(critical_flag AS FLOAT64)) AS pct_with_critical_labs
  FROM pancreatitis_quintiles
  GROUP BY instability_quintile
  ORDER BY instability_quintile
),

-- Controls: age-matched female inpatients WITHOUT pancreatitis (exclude any hadm in pancreatitis_adms)
controls_adms AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.hadm_id NOT IN (SELECT hadm_id FROM pancreatitis_adms)
),

-- Compute control lab stats using same lab set, time window, and critical definition
controls_lab_stats AS (
  SELECT
    ca.hadm_id,
    COUNT(CASE WHEN ll.itemid IS NOT NULL AND le.valuenum IS NOT NULL THEN 1 END) AS total_labs,
    MAX(CASE
          WHEN ll.itemid IS NOT NULL
            AND le.valuenum IS NOT NULL
            AND SAFE_CAST(le.ref_range_lower AS FLOAT64) IS NOT NULL
            AND SAFE_CAST(le.ref_range_upper AS FLOAT64) IS NOT NULL
            AND (
                 CAST(le.valuenum AS FLOAT64) < (SAFE_CAST(le.ref_range_lower AS FLOAT64) * 0.5)
                 OR CAST(le.valuenum AS FLOAT64) > (SAFE_CAST(le.ref_range_upper AS FLOAT64) * 1.5)
               )
          THEN 1
          ELSE 0
        END) AS critical_flag
  FROM controls_adms ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = ca.hadm_id
   AND le.charttime >= ca.admittime
   AND le.charttime < TIMESTAMP_ADD(ca.admittime, INTERVAL 48 HOUR)
  LEFT JOIN lab_list ll
    ON le.itemid = ll.itemid
  GROUP BY ca.hadm_id
),

-- control-level filtering: keep only admissions with at least one lab
controls_with_labs AS (
  SELECT hadm_id, critical_flag
  FROM controls_lab_stats
  WHERE total_labs > 0
),

-- compute overall percent with critical labs among age-matched controls
control_critical_pct AS (
  SELECT
    100.0 * AVG(CAST(critical_flag AS FLOAT64)) AS pct_with_critical_labs_controls
  FROM controls_with_labs
)

-- Final: combine quintile aggregates with the control percent for comparison
SELECT
  qa.instability_quintile,
  qa.n_admissions,
  ROUND(qa.mean_instability, 4) AS mean_instability,
  ROUND(qa.mean_los_days, 2) AS mean_los_days,
  ROUND(qa.mortality_pct, 2) AS mortality_pct,
  ROUND(qa.pct_with_critical_labs, 2) AS pct_with_critical_labs,
  ROUND(cc.pct_with_critical_labs_controls, 2) AS pct_with_critical_labs_age_matched_controls
FROM quintile_aggregates qa
CROSS JOIN control_critical_pct cc
ORDER BY qa.instability_quintile;