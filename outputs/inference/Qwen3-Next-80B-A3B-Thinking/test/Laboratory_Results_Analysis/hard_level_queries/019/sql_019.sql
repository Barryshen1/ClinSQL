WITH ap_patients AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.gender, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON d.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  WHERE d.icd_version = 10
    AND d.icd_code LIKE 'K85%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
),

lab_abnormal AS (
  SELECT 
    ap.subject_id,
    ap.hadm_id,
    COUNT(*) AS abnormal_count
  FROM ap_patients ap
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON ap.subject_id = le.subject_id AND ap.hadm_id = le.hadm_id
  WHERE le.charttime >= ap.admittime
    AND le.charttime <= ap.admittime + INTERVAL 72 HOUR
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
  GROUP BY ap.subject_id, ap.hadm_id
),

p90 AS (
  SELECT PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY abnormal_count) AS p90_val
  FROM lab_abnormal
),

high_risk_patients AS (
  SELECT 
    ap.subject_id,
    ap.hadm_id,
    ap.admittime,
    ap.dischtime,
    ap.hospital_expire_flag
  FROM ap_patients ap
  JOIN lab_abnormal la 
    ON ap.subject_id = la.subject_id AND ap.hadm_id = la.hadm_id
  CROSS JOIN p90
  WHERE la.abnormal_count >= p90.p90_val
),

high_risk_total AS (
  SELECT COUNT(DISTINCT subject_id) AS total_high_risk
  FROM high_risk_patients
),

general_total AS (
  SELECT COUNT(DISTINCT subject_id) AS total_general
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

lab_critical_rates_high AS (
  SELECT 
    le.itemid,
    COUNT(DISTINCT hrp.subject_id) / hrt.total_high_risk AS critical_rate_high
  FROM high_risk_patients hrp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON hrp.subject_id = le.subject_id AND hrp.hadm_id = le.hadm_id
  CROSS JOIN high_risk_total hrt
  WHERE le.charttime >= hrp.admittime
    AND le.charttime <= hrp.admittime + INTERVAL 72 HOUR
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
  GROUP BY le.itemid, hrt.total_high_risk
),

lab_critical_rates_general AS (
  SELECT 
    le.itemid,
    COUNT(DISTINCT p.subject_id) / gt.total_general AS critical_rate_general
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON p.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
  CROSS JOIN general_total gt
  WHERE le.charttime >= a.admittime
    AND le.charttime <= a.admittime + INTERVAL 72 HOUR
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
  GROUP BY le.itemid, gt.total_general
),

mortality_and_los AS (
  SELECT 
    AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)) / 24.0 AS mean_los_days
  FROM high_risk_patients
)

SELECT 
  'mortality' AS metric,
  mortality_rate AS value,
  NULL AS critical_rate_high,
  NULL AS critical_rate_general
FROM mortality_and_los
UNION ALL
SELECT 
  'mean_los' AS metric,
  mean_los_days AS value,
  NULL AS critical_rate_high,
  NULL AS critical_rate_general
FROM mortality_and_los
UNION ALL
SELECT 
  'lab_' || CAST(lch.itemid AS STRING) AS metric,
  NULL AS value,
  lch.critical_rate_high,
  lcg.critical_rate_general
FROM lab_critical_rates_high lch
JOIN lab_critical_rates_general lcg 
  ON lch.itemid = lcg.itemid;