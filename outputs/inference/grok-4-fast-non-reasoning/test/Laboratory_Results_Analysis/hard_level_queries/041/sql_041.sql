WITH hf_cohort AS (
  -- Heart failure cohort: males 54-64, inpatients
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND a.admission_location != 'EMERGENCY DEPARTMENT'
    AND (
      -- ICD-10 heart failure
      (d.icd_version = '10' AND (d.icd_code LIKE 'I50%' OR d.icd_code = 'I11.0'))
      -- ICD-9 heart failure
      OR (d.icd_version = '9' AND d.icd_code LIKE '428%')
    )
    AND ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1  -- First admission
),

control_cohort AS (
  -- Age-matched controls: males 54-64, inpatients, no HF
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND a.admission_location != 'EMERGENCY DEPARTMENT'
    AND NOT (
      (d.icd_version = '10' AND (d.icd_code LIKE 'I50%' OR d.icd_code = 'I11.0'))
      OR (d.icd_version = '9' AND d.icd_code LIKE '428%')
    )
    AND ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),

first_labs AS (
  -- First lab values in first 48h for key HF-relevant labs (HF cohort)
  SELECT 
    l.subject_id, l.hadm_id, l.itemid,
    FIRST_VALUE(l.valuenum) OVER (PARTITION BY l.subject_id, l.hadm_id, l.itemid ORDER BY l.charttime) AS valuenum,
    FIRST_VALUE(l.valueuom) OVER (PARTITION BY l.subject_id, l.hadm_id, l.itemid ORDER BY l.charttime) AS valueuom,
    FIRST_VALUE(l.charttime) OVER (PARTITION BY l.subject_id, l.hadm_id, l.itemid ORDER BY l.charttime) AS charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN hf_cohort h ON l.subject_id = h.subject_id AND l.hadm_id = h.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  WHERE l.charttime >= h.admittime 
    AND l.charttime <= TIMESTAMP_ADD(h.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
    AND li.category = 'Chemistry'
    AND li.itemid IN (50912, 51006, 50983, 50971, 50586, 51277)  -- Creatinine, BUN, Na, K, BNP variants
),

control_labs AS (
  -- First lab values in first 48h for controls (mirroring first_labs)
  SELECT 
    l.subject_id, l.hadm_id, l.itemid,
    FIRST_VALUE(l.valuenum) OVER (PARTITION BY l.subject_id, l.hadm_id, l.itemid ORDER BY l.charttime) AS valuenum,
    FIRST_VALUE(l.valueuom) OVER (PARTITION BY l.subject_id, l.hadm_id, l.itemid ORDER BY l.charttime) AS valueuom,
    FIRST_VALUE(l.charttime) OVER (PARTITION BY l.subject_id, l.hadm_id, l.itemid ORDER BY l.charttime) AS charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN control_cohort h ON l.subject_id = h.subject_id AND l.hadm_id = h.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  WHERE l.charttime >= h.admittime 
    AND l.charttime <= TIMESTAMP_ADD(h.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
    AND li.category = 'Chemistry'
    AND li.itemid IN (50912, 51006, 50983, 50971, 50586, 51277)
),

lab_scores AS (
  -- Compute per-lab instability (deviation from ref range)
  SELECT 
    subject_id, hadm_id,
    CASE 
      WHEN itemid = 50912 THEN SAFE_DIV(ABS(valuenum - 1.0), 1.0 * 0.1)  -- Creatinine mg/dL, ref ~0.7-1.3, mid=1.0
      WHEN itemid = 51006 THEN SAFE_DIV(ABS(valuenum - 13.5), 13.5 * 0.1)  -- BUN mg/dL, ref 7-20, mid=13.5
      WHEN itemid = 50983 THEN SAFE_DIV(ABS(valuenum - 140), 140 * 0.1)  -- Na mEq/L, ref 135-145, mid=140
      WHEN itemid = 50971 THEN SAFE_DIV(ABS(valuenum - 4.25), 4.25 * 0.1)  -- K mEq/L, ref 3.5-5.0, mid=4.25
      WHEN itemid IN (50586, 51277) THEN SAFE_DIV(ABS(valuenum - 50), 50 * 0.1)  -- BNP pg/mL, ref <100, conservative mid=50
      ELSE 0 
    END AS instability,
    itemid
  FROM first_labs
  WHERE valuenum IS NOT NULL
),

patient_scores AS (
  -- Aggregate total score per patient (sum, cap per lab at 10)
  SELECT 
    subject_id, hadm_id,
    LEAST(SUM(LEAST(instability, 10)), 50) AS total_score  -- Max 10 per lab, 5 labs
  FROM lab_scores
  GROUP BY subject_id, hadm_id
  HAVING total_score IS NOT NULL  -- Exclude no labs
),

threshold AS (
  SELECT PERCENTILE_CONT(0.95, total_score) AS p95_threshold
  FROM patient_scores
),

high_risk AS (
  SELECT ps.*, h.dischtime, h.admittime, h.hospital_expire_flag,
    TIMESTAMP_DIFF(h.dischtime, h.admittime, HOUR) / 24.0 AS los_days
  FROM patient_scores ps
  INNER JOIN hf_cohort h ON ps.hadm_id = h.hadm_id
  CROSS JOIN threshold t
  WHERE total_score >= t.p95_threshold
),

high_risk_critical_labs AS (
  -- Critical labs for high-risk (e.g., severe derangements)
  SELECT hr.subject_id, hr.hadm_id,
    MAX(CASE 
      WHEN fl.itemid = 50912 AND fl.valuenum > 4 THEN 1  -- Creatinine >4 mg/dL
      WHEN fl.itemid = 50971 AND (fl.valuenum > 6 OR fl.valuenum < 2.5) THEN 1  -- K extreme
      WHEN fl.itemid = 50983 AND (fl.valuenum > 160 OR fl.valuenum < 120) THEN 1  -- Na extreme
      WHEN fl.itemid IN (50586, 51277) AND fl.valuenum > 1000 THEN 1  -- BNP >1000
      ELSE 0 
    END) AS has_critical_lab
  FROM high_risk hr
  INNER JOIN first_labs fl ON hr.hadm_id = fl.hadm_id
  GROUP BY hr.subject_id, hr.hadm_id
),

control_critical_labs AS (
  -- Same for controls
  SELECT cc.subject_id, cc.hadm_id,
    MAX(CASE 
      WHEN fl.itemid = 50912 AND fl.valuenum > 4 THEN 1
      WHEN fl.itemid = 50971 AND (fl.valuenum > 6 OR fl.valuenum < 2.5) THEN 1
      WHEN fl.itemid = 50983 AND (fl.valuenum > 160 OR fl.valuenum < 120) THEN 1
      WHEN fl.itemid IN (50586, 51277) AND fl.valuenum > 1000 THEN 1
      ELSE 0 
    END) AS has_critical_lab
  FROM control_cohort cc
  LEFT JOIN control_labs fl ON cc.hadm_id = fl.hadm_id
  GROUP BY cc.subject_id, cc.hadm_id
)

-- Final results
SELECT 
  'HF High-Risk (score >= 95th percentile)' AS group_name,
  t.p95_threshold AS instability_threshold,
  ROUND(AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS mortality_pct,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(AVG(CASE WHEN hcl.has_critical_lab = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS critical_lab_rate_pct
FROM high_risk hr
CROSS JOIN threshold t
LEFT JOIN high_risk_critical_labs hcl ON hr.hadm_id = hcl.hadm_id

UNION ALL

SELECT 
  'Age-Matched Controls' AS group_name,
  NULL AS instability_threshold,
  ROUND(AVG(CASE WHEN cc.hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS mortality_pct,
  ROUND(AVG(TIMESTAMP_DIFF(cc.dischtime, cc.admittime, HOUR) / 24.0), 2) AS mean_los_days,
  ROUND(AVG(CASE WHEN ccl.has_critical_lab = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS critical_lab_rate_pct
FROM control_cohort cc
LEFT JOIN control_critical_labs ccl ON cc.hadm_id = ccl.hadm_id
ORDER BY group_name;