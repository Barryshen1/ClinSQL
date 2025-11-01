WITH hhs_cohort AS (
  -- Base cohort: females 50-60 with HHS (primary dx)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
    AND EXTRACT(YEAR FROM a.admittime) >= p.anchor_year
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d.icd_version = '10'
    AND d.icd_code IN ('E11.00', 'E11.01', 'E13.00', 'E13.10', 'E13.11')
    AND d.seq_num = 1
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
),

lab_measures AS (
  -- First labs within 48h for key items
  SELECT 
    hc.hadm_id,
    le.itemid,
    le.valuenum,
    COALESCE(le.ref_range_lower, 
      CASE le.itemid 
        WHEN 225655 THEN 70 WHEN 227438 THEN 135 WHEN 227464 THEN 3.5 
        WHEN 225624 THEN 7 WHEN 225625 THEN 0.6 
        ELSE NULL END) AS lower_range,
    COALESCE(le.ref_range_upper, 
      CASE le.itemid 
        WHEN 225655 THEN 110 WHEN 227438 THEN 145 WHEN 227464 THEN 5.0 
        WHEN 225624 THEN 20 WHEN 225625 THEN 1.2 
        ELSE NULL END) AS upper_range
  FROM hhs_cohort hc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON hc.subject_id = le.subject_id 
    AND le.hadm_id = hc.hadm_id
    AND le.itemid IN (225655, 227438, 227464, 225624, 225625)  -- glucose, Na, K, BUN, Cr
    AND le.charttime >= hc.admittime
    AND le.charttime <= TIMESTAMP_ADD(hc.admittime, INTERVAL 2 DAY)
    AND le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id, le.itemid ORDER BY le.charttime) = 1
),

instability_scores AS (
  -- Compute per-lab deviation and average score per admission
  SELECT 
    hc.hadm_id,
    hc.hospital_expire_flag,
    hc.los_days,
    AVG(
      CASE 
        WHEN lm.lower_range IS NOT NULL AND lm.upper_range IS NOT NULL AND lm.upper_range > lm.lower_range AND lm.valuenum IS NOT NULL
        THEN LEAST(ABS(lm.valuenum - (lm.lower_range + lm.upper_range)/2) / ((lm.upper_range - lm.lower_range)/2) * 100, 100)
        ELSE NULL 
      END
    ) AS instability_score
  FROM hhs_cohort hc
  LEFT JOIN lab_measures lm ON hc.hadm_id = lm.hadm_id
  GROUP BY hc.hadm_id, hc.hospital_expire_flag, hc.los_days
  HAVING COUNT(DISTINCT lm.itemid) >= 3  -- ensure at least 3 valid labs for HHS context
),

threshold AS (
  SELECT PERCENTILE_CONT(0.75, instability_score) OVER() AS score_75th
  FROM instability_scores
),

high_score_stats AS (
  SELECT 
    COUNT(*) AS num_admissions,
    AVG(is.los_days) AS mean_los_days,
    AVG(CASE WHEN is.hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) AS mortality_rate,
    -- Critical lab rate: % with any lab outside range (instability > 0 implies deviation)
    AVG(CASE WHEN is.instability_score > 0 THEN 1.0 ELSE 0 END) AS critical_lab_rate
  FROM instability_scores is
  CROSS JOIN threshold t
  WHERE is.instability_score >= t.score_75th
),

general_cohort AS (
  -- General female 50-60 inpatients (for comparison, exclude HHS)
  SELECT 
    a.hadm_id,
    a.dischtime,
    a.admittime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
    AND EXTRACT(YEAR FROM a.admittime) >= p.anchor_year
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    AND d.icd_version = '10'
    AND d.icd_code IN ('E11.00', 'E11.01', 'E13.00', 'E13.10', 'E13.11')
    AND d.seq_num = 1
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d.hadm_id IS NULL  -- exclude HHS
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
),

general_lab_measures AS (
  -- First labs within 48h for general cohort; flag if out-of-range
  SELECT 
    gc.hadm_id,
    le.itemid,
    CASE 
      WHEN le.valuenum < COALESCE(le.ref_range_lower, 
        CASE le.itemid WHEN 225655 THEN 70 WHEN 227438 THEN 135 WHEN 227464 THEN 3.5 
                       WHEN 225624 THEN 7 WHEN 225625 THEN 0.6 ELSE NULL END)
         OR le.valuenum > COALESCE(le.ref_range_upper, 
        CASE le.itemid WHEN 225655 THEN 110 WHEN 227438 THEN 145 WHEN 227464 THEN 5.0 
                       WHEN 225624 THEN 20 WHEN 225625 THEN 1.2 ELSE NULL END)
      THEN 1 ELSE 0 
    END AS is_critical
  FROM general_cohort gc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON gc.subject_id = le.subject_id
    AND le.hadm_id = gc.hadm_id
    AND le.charttime >= gc.admittime
    AND le.charttime <= TIMESTAMP_ADD(gc.admittime, INTERVAL 2 DAY)
    AND le.itemid IN (225655, 227438, 227464, 225624, 225625)
    AND le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id, le.itemid ORDER BY le.charttime) = 1
),

general_critical_rate AS (
  SELECT 
    gc.hadm_id,
    MAX(COALESCE(glm.is_critical, 0)) AS has_critical_lab
  FROM general_cohort gc
  LEFT JOIN general_lab_measures glm ON gc.hadm_id = glm.hadm_id
  GROUP BY gc.hadm_id
),

general_stats AS (
  SELECT 
    COUNT(*) AS num_admissions,
    AVG(gc.los_days) AS mean_los_days,
    AVG(CASE WHEN gc.hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) AS mortality_rate,
    AVG(gcr.has_critical_lab) AS critical_lab_rate
  FROM general_cohort gc
  LEFT JOIN general_critical_rate gcr ON gc.hadm_id = gcr.hadm_id
)

-- Main results: 75th percentile, high-score stats, general comparison
SELECT 
  (SELECT score_75th FROM threshold) AS p75_instability_score,
  hss.num_admissions AS high_score_num_admissions,
  ROUND(hss.mean_los_days, 2) AS high_score_mean_los_days,
  ROUND(hss.mortality_rate * 100, 2) AS high_score_mortality_pct,
  ROUND(hss.critical_lab_rate * 100, 2) AS high_score_critical_lab_rate_pct,
  gs.num_admissions AS general_num_admissions,
  ROUND(gs.mean_los_days, 2) AS general_mean_los_days,
  ROUND(gs.mortality_rate * 100, 2) AS general_mortality_pct,
  ROUND(gs.critical_lab_rate * 100, 2) AS general_critical_lab_rate_pct,
  ROUND((hss.critical_lab_rate - gs.critical_lab_rate) * 100, 2) AS critical_lab_rate_diff_pct
FROM high_score_stats hss
CROSS JOIN general_stats gs;