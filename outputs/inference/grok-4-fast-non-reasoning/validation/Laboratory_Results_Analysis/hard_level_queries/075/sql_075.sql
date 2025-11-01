WITH dvt_cohort AS (
  -- Select male patients aged 42-52 with DVT admissions
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'I82.4%' OR d.icd_code LIKE 'I82.5%' OR d.icd_code LIKE 'I82.9%')
),

lab_instability AS (
  -- Compute instability for key labs in first 72 hours
  SELECT 
    le.subject_id,
    le.hadm_id,
    -- Deviation from mid-normal, normalized
    SAFE_DIVIDE(
      ABS(le.valuenum - 
        COALESCE(
          (le.ref_range_lower + le.ref_range_upper) / 2,
          0  -- Fallback if no range
        )
      ),
      GREATEST(
        (le.ref_range_upper - le.ref_range_lower) / 2,
        1  -- Avoid divide by zero, min width 1
      )
    ) AS instability
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN dvt_cohort dc ON le.subject_id = dc.subject_id AND le.hadm_id = dc.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.charttime BETWEEN dc.admittime AND TIMESTAMP_ADD(dc.admittime, INTERVAL 3 DAY)
    AND di.category IN ('Chemistry', 'Hematology', 'Coagulation')
    AND di.label IN (
      'Creatinine', 'Potassium', 'Sodium', 
      'WBC', 'Platelet count', 
      'INR(PT)', 'PTT'
    )
),

patient_scores AS (
  -- Aggregate to per-admission score
  SELECT 
    subject_id,
    hadm_id,
    AVG(COALESCE(instability, 0)) AS lab_instability_score
  FROM lab_instability
  GROUP BY subject_id, hadm_id
),

all_scores AS (
  -- All cohort scores for percentile
  SELECT lab_instability_score
  FROM patient_scores
),

p95_score AS (
  SELECT APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(95)] AS percentile_95
  FROM all_scores
),

high_risk AS (
  -- High-risk admissions
  SELECT ps.*, dc.dischtime, dc.hospital_expire_flag, dc.admittime
  FROM patient_scores ps
  INNER JOIN dvt_cohort dc ON ps.subject_id = dc.subject_id AND ps.hadm_id = dc.hadm_id
  CROSS JOIN p95_score p95
  WHERE ps.lab_instability_score >= p95.percentile_95
),

all_inpatients_critical AS (
  -- Critical lab rates for all inpatients (benchmark)
  SELECT 
    COUNTIF(LOWER(le.flag) = 'abnormal') / COUNT(le.labevent_id) AS critical_lab_rate_all
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 3 DAY)
    AND le.flag IS NOT NULL
),

high_risk_critical AS (
  -- Critical lab rates for high-risk
  SELECT 
    COUNTIF(LOWER(le.flag) = 'abnormal') / COUNT(le.labevent_id) AS critical_lab_rate_highrisk
  FROM high_risk hr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON hr.subject_id = le.subject_id AND hr.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN hr.admittime AND TIMESTAMP_ADD(hr.admittime, INTERVAL 3 DAY)
    AND le.flag IS NOT NULL
)

-- Final summary
SELECT 
  p95.percentile_95 AS p95_lab_instability_score,
  COUNT(hr.subject_id) AS num_high_risk_admissions,
  SAFE_DIVIDE(
    COUNTIF(hr.hospital_expire_flag = 1), 
    COUNT(hr.subject_id)
  ) AS mortality_rate_highrisk,
  AVG(DATE_DIFF(hr.dischtime, hr.admittime, DAY)) AS mean_los_days_highrisk,
  hrc.critical_lab_rate_highrisk,
  aic.critical_lab_rate_all
FROM p95_score p95
LEFT JOIN high_risk hr ON 1=1
CROSS JOIN high_risk_critical hrc
CROSS JOIN all_inpatients_critical aic
GROUP BY p95.percentile_95, hrc.critical_lab_rate_highrisk, aic.critical_lab_rate_all;