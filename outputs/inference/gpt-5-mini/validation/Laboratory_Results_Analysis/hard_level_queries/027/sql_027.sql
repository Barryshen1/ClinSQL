WITH
-- 1) all male inpatients aged 89-99
male_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
),

-- 2) identify admissions with a lower GI bleed diagnosis (text-search in diagnosis description)
lower_gi_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code
   AND d.icd_version = diag.icd_version
  WHERE (
    LOWER(diag.long_title) LIKE '%lower gastrointestinal%'
    OR LOWER(diag.long_title) LIKE '%lower gi%'
    OR LOWER(diag.long_title) LIKE '%gastrointestinal hemorrhage%'
    OR LOWER(diag.long_title) LIKE '%rectal%'
    OR LOWER(diag.long_title) LIKE '%rectum%'
    OR LOWER(diag.long_title) LIKE '%colonic%'
    OR LOWER(diag.long_title) LIKE '%diverticulosis%'
  )
),

-- 3) aggregate labs within first 72 hours of admission for all male admissions
labs_72h AS (
  SELECT
    le.hadm_id,
    SUM(CASE WHEN le.flag IS NOT NULL AND TRIM(le.flag) != '' THEN 1 ELSE 0 END) AS n_abnormal,
    COUNT(1) AS n_labs
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN male_admissions ma
    ON le.hadm_id = ma.hadm_id
  WHERE le.charttime IS NOT NULL
    AND le.charttime BETWEEN ma.admittime AND TIMESTAMP_ADD(ma.admittime, INTERVAL 72 HOUR)
  GROUP BY le.hadm_id
),

-- 4) combine admissions with lab aggregates and annotate lower-GI flag
adm_with_labs AS (
  SELECT
    ma.subject_id,
    ma.hadm_id,
    ma.admittime,
    ma.dischtime,
    ma.hospital_expire_flag,
    ma.anchor_age,
    CASE WHEN lg.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_lower_gi,
    COALESCE(l.n_abnormal, 0) AS instability_score,
    CASE WHEN COALESCE(l.n_abnormal, 0) > 0 THEN 1 ELSE 0 END AS has_critical_lab
  FROM male_admissions ma
  LEFT JOIN lower_gi_hadm lg
    ON ma.hadm_id = lg.hadm_id
  LEFT JOIN labs_72h l
    ON ma.hadm_id = l.hadm_id
),

-- 5) compute quintiles among lower-GI admissions (higher instability_score -> higher quintile)
lower_gi_quintiles AS (
  SELECT
    a.*,
    -- compute LOS in days as fractional days (seconds / 86400)
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400.0) AS los_days,
    NTILE(5) OVER (ORDER BY a.instability_score DESC) AS quintile
  FROM adm_with_labs a
  WHERE a.is_lower_gi = 1
),

-- 6) aggregate per quintile
quintile_stats AS (
  SELECT
    quintile,
    COUNT(1) AS n_admissions,
    -- approximate median LOS using APPROX_QUANTILES (2 quantiles => median at offset 1)
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
    -- hospital mortality rate
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(1)) AS mortality_rate,
    -- proportion with at least one flagged (critical) lab in first 72h for this quintile
    SAFE_DIVIDE(SUM(has_critical_lab), COUNT(1)) AS quintile_critical_lab_rate
  FROM lower_gi_quintiles
  GROUP BY quintile
  ORDER BY quintile
),

-- 7) compute the general inpatient critical-lab rate among all male inpatients age 89-99
general_rate AS (
  SELECT
    COUNT(1) AS n_general_admissions,
    SAFE_DIVIDE(SUM(has_critical_lab), COUNT(1)) AS general_critical_lab_rate
  FROM adm_with_labs
)

-- Final: present per-quintile stats and attach general rate for comparison
SELECT
  q.quintile,
  q.n_admissions,
  ROUND(q.median_los_days, 2) AS median_los_days,
  ROUND(q.mortality_rate * 100, 1) AS mortality_pct,
  ROUND(q.quintile_critical_lab_rate * 100, 1) AS quintile_critical_lab_pct,
  ROUND(g.general_critical_lab_rate * 100, 1) AS general_inpatient_critical_lab_pct,
  g.n_general_admissions
FROM quintile_stats q
CROSS JOIN general_rate g
ORDER BY q.quintile;