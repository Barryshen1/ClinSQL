WITH first_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

acs_cohort AS (
  -- Define ACS cohort: females 40-50 with ACS diagnosis, first admission only
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN first_admissions fa
    ON a.subject_id = fa.subject_id AND a.hadm_id = fa.hadm_id AND fa.rn = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND d.icd_version = '10'
    AND (d.icd_code = 'I20.0'  -- Unstable angina
         OR d.icd_code LIKE 'I21.%')  -- Acute MI
),

lab_scores AS (
  -- Compute first-48h instability score per patient (simplified: avg |valuenum - ref midpoint| / ref width)
  SELECT 
    ac.subject_id,
    ac.hadm_id,
    ac.admittime,
    ac.dischtime,
    ac.hospital_expire_flag,
    ac.anchor_age,
    AVG(
      CASE 
        WHEN l.ref_range_lower IS NOT NULL AND l.ref_range_upper IS NOT NULL AND l.ref_range_upper > l.ref_range_lower
        THEN ABS(l.valuenum - (l.ref_range_lower + l.ref_range_upper)/2.0) / ((l.ref_range_upper - l.ref_range_lower)/2.0)
        ELSE NULL 
      END
    ) AS instability_score
  FROM acs_cohort ac
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON ac.subject_id = l.subject_id AND ac.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li 
    ON CAST(l.itemid AS STRING) = li.itemid
  WHERE l.charttime BETWEEN TIMESTAMP(ac.admittime) AND TIMESTAMP_ADD(TIMESTAMP(ac.admittime), INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
    AND li.category IN ('Chemistry', 'Blood Gas', 'Hematology')  -- Relevant panels
    AND l.itemid IN (  -- Key ACS labs
      50010, 50015, 50020, 50025, 50030, 
      50040, 50050, 50060, 50070, 50075, 
      50809, 51222, 51312  -- e.g., Creat, BUN, AST, ALT, Na, K, WBC, etc.
    )
    AND l.ref_range_lower IS NOT NULL AND l.ref_range_upper IS NOT NULL
  GROUP BY ac.subject_id, ac.hadm_id, ac.admittime, ac.dischtime, ac.hospital_expire_flag, ac.anchor_age
  HAVING COUNT(l.valuenum) > 0  -- At least some labs
),

threshold AS (
  -- 90th percentile score (aggregate to single value)
  SELECT 
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90_score
  FROM lab_scores
),

high_risk AS (
  -- High-risk: score >= p90; simplified critical lab flag
  SELECT 
    ls.*,
    t.p90_score,
    CASE WHEN ls.instability_score >= t.p90_score THEN 1 ELSE 0 END AS high_risk_flag,
    CASE WHEN ls.instability_score > 2 THEN 1 ELSE 0 END AS has_critical_lab  -- Proxy: score >2 indicates critical deviation
  FROM lab_scores ls
  CROSS JOIN threshold t
),

general_cohort AS (
  -- General inpatients: all females 40-50, first admission
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    0 AS high_risk_flag,
    0 AS has_critical_lab,
    0.0 AS instability_score,  -- Placeholder
    0.0 AS p90_score
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN first_admissions fa
    ON a.subject_id = fa.subject_id AND a.hadm_id = fa.hadm_id AND fa.rn = 1
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),

outcomes AS (
  -- Metrics for high-risk ACS
  SELECT 
    'High-risk ACS' AS group_type,
    COUNT(*) AS n_patients,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(TIMESTAMP(dischtime), TIMESTAMP(admittime), HOUR) / 24.0) AS mean_los_days,
    AVG(CAST(has_critical_lab AS FLOAT64)) AS critical_lab_rate,
    (SELECT p90_score FROM threshold) AS p90_threshold
  FROM high_risk
  WHERE high_risk_flag = 1

  UNION ALL

  -- Metrics for general inpatients
  SELECT 
    'General Inpatients' AS group_type,
    COUNT(*) AS n_patients,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(TIMESTAMP(dischtime), TIMESTAMP(admittime), HOUR) / 24.0) AS mean_los_days,
    0.0 AS critical_lab_rate,  -- Placeholder (no lab computation for general)
    (SELECT p90_score FROM threshold) AS p90_threshold
  FROM general_cohort
)

SELECT 
  group_type,
  n_patients,
  ROUND(mortality_rate * 100, 2) AS mortality_pct,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(critical_lab_rate * 100, 2) AS critical_lab_rate_pct,
  ROUND(p90_threshold, 2) AS p90_threshold
FROM outcomes
ORDER BY CASE WHEN group_type = 'High-risk ACS' THEN 1 ELSE 0 END DESC;