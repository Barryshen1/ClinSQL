WITH
-- 1) Define lab test groups (critical labs) via label pattern matching in d_labitems
lab_targets AS (
  SELECT itemid, label,
    CASE
      WHEN LOWER(label) LIKE '%potassium%' THEN 'potassium'
      WHEN LOWER(label) LIKE '%sodium%' THEN 'sodium'
      WHEN LOWER(label) LIKE '%hemoglobin%' OR LOWER(label) LIKE '%hb%' THEN 'hemoglobin'
      WHEN LOWER(label) LIKE '%platelet%' THEN 'platelets'
      WHEN LOWER(label) LIKE '%inr%' OR LOWER(label) LIKE '%international normalized ratio%' THEN 'inr'
      WHEN LOWER(label) LIKE '%creatinine%' THEN 'creatinine'
      WHEN LOWER(label) LIKE '%glucose%' OR LOWER(label) LIKE '%blood sugar%' THEN 'glucose'
      ELSE NULL
    END AS lab_name
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%potassium%'
     OR LOWER(label) LIKE '%sodium%'
     OR LOWER(label) LIKE '%hemoglobin%'
     OR LOWER(label) LIKE '%hb%'
     OR LOWER(label) LIKE '%platelet%'
     OR LOWER(label) LIKE '%inr%'
     OR LOWER(label) LIKE '%creatinine%'
     OR LOWER(label) LIKE '%glucose%'
),

-- 2) Base set: admissions for female patients age 74-84
age_gender_admissions AS (
  SELECT a.*, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p USING (subject_id)
  WHERE SUBSTR(UPPER(TRIM(p.gender)), 1, 1) = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
),

-- 3) Identify ICH admissions via diagnosis text match (pragmatic)
ich_admissions AS (
  SELECT DISTINCT aga.hadm_id
  FROM age_gender_admissions aga
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON aga.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE (
        LOWER(COALESCE(dd.long_title, '')) LIKE '%intracranial%'
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%intracerebral%'
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%subarachnoid%'
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%subdural%'
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%hematoma%'
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%intracranial hemorrhag%'
     )
),

-- 4) All relevant lab events in first 72 hours for the age/gender cohort
labs_72h AS (
  SELECT
    a.hadm_id,
    le.subject_id,
    le.itemid,
    le.charttime,
    le.valuenum,
    SAFE_CAST(le.ref_range_lower AS FLOAT64) AS ref_low,
    SAFE_CAST(le.ref_range_upper AS FLOAT64) AS ref_high,
    le.flag,
    -- abnormal criteria: numeric out of range OR textual abnormal flag
    CASE
      WHEN le.valuenum IS NOT NULL
           AND (
                (SAFE_CAST(le.ref_range_lower AS FLOAT64) IS NOT NULL AND le.valuenum < SAFE_CAST(le.ref_range_lower AS FLOAT64))
             OR (SAFE_CAST(le.ref_range_upper AS FLOAT64) IS NOT NULL AND le.valuenum > SAFE_CAST(le.ref_range_upper AS FLOAT64))
           ) THEN TRUE
      WHEN LOWER(COALESCE(le.flag, '')) LIKE '%abnorm%' THEN TRUE
      ELSE FALSE
    END AS is_abnormal
  FROM age_gender_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
),

-- 5) Map lab events to critical lab names (if in lab_targets)
labs_72h_mapped AS (
  SELECT l.*, lt.lab_name
  FROM labs_72h l
  LEFT JOIN lab_targets lt
    ON l.itemid = lt.itemid
),

-- 6) Per-admission summary: distinct abnormal lab count and per-critical-lab abnormal flags
admission_lab_summary AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- fractional LOS in days
    (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS los_days,
    -- distinct abnormal lab tests in first 72h (count distinct itemid where abnormal)
    COALESCE(ab.distinct_abn_count, 0) AS abnormal_lab_count,
    -- per-critical-lab abnormal flag (1/0)
    COALESCE(MAX(CASE WHEN m.lab_name = 'potassium' AND m.is_abnormal THEN 1 ELSE 0 END), 0) AS abn_potassium,
    COALESCE(MAX(CASE WHEN m.lab_name = 'sodium' AND m.is_abnormal THEN 1 ELSE 0 END), 0) AS abn_sodium,
    COALESCE(MAX(CASE WHEN m.lab_name = 'hemoglobin' AND m.is_abnormal THEN 1 ELSE 0 END), 0) AS abn_hemoglobin,
    COALESCE(MAX(CASE WHEN m.lab_name = 'platelets' AND m.is_abnormal THEN 1 ELSE 0 END), 0) AS abn_platelets,
    COALESCE(MAX(CASE WHEN m.lab_name = 'inr' AND m.is_abnormal THEN 1 ELSE 0 END), 0) AS abn_inr,
    COALESCE(MAX(CASE WHEN m.lab_name = 'creatinine' AND m.is_abnormal THEN 1 ELSE 0 END), 0) AS abn_creatinine,
    COALESCE(MAX(CASE WHEN m.lab_name = 'glucose' AND m.is_abnormal THEN 1 ELSE 0 END), 0) AS abn_glucose
  FROM age_gender_admissions a
  LEFT JOIN (
    SELECT hadm_id, COUNT(DISTINCT itemid) AS distinct_abn_count
    FROM labs_72h
    WHERE is_abnormal = TRUE
    GROUP BY hadm_id
  ) ab ON a.hadm_id = ab.hadm_id
  LEFT JOIN labs_72h_mapped m
    ON a.hadm_id = m.hadm_id AND m.is_abnormal = TRUE
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag, ab.distinct_abn_count
),

-- 7) Cases (ICH admissions) and Controls (age/gender matched without ICH)
case_admissions AS (
  SELECT als.*
  FROM admission_lab_summary als
  JOIN ich_admissions ic ON als.hadm_id = ic.hadm_id
),
control_admissions AS (
  SELECT als.*
  FROM admission_lab_summary als
  LEFT JOIN ich_admissions ic ON als.hadm_id = ic.hadm_id
  WHERE ic.hadm_id IS NULL
),

-- 8) Assign quintiles to cases based on abnormal_lab_count
case_with_quintile AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY abnormal_lab_count) AS quintile
  FROM case_admissions
),

-- 9) Aggregate case stats by quintile
case_quintile_stats AS (
  SELECT
    quintile,
    COUNT(*) AS n_admissions,
    ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_pct,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    ROUND(100.0 * SUM(abn_potassium) / COUNT(*), 2) AS pct_abn_potassium,
    ROUND(100.0 * SUM(abn_sodium) / COUNT(*), 2) AS pct_abn_sodium,
    ROUND(100.0 * SUM(abn_hemoglobin) / COUNT(*), 2) AS pct_abn_hemoglobin,
    ROUND(100.0 * SUM(abn_platelets) / COUNT(*), 2) AS pct_abn_platelets,
    ROUND(100.0 * SUM(abn_inr) / COUNT(*), 2) AS pct_abn_inr,
    ROUND(100.0 * SUM(abn_creatinine) / COUNT(*), 2) AS pct_abn_creatinine,
    ROUND(100.0 * SUM(abn_glucose) / COUNT(*), 2) AS pct_abn_glucose,
    MIN(abnormal_lab_count) AS min_abn_count_in_quintile,
    MAX(abnormal_lab_count) AS max_abn_count_in_quintile
  FROM case_with_quintile
  GROUP BY quintile
  ORDER BY quintile
),

-- 10) Compute overall control rates for the same critical labs (age/gender matched, non-ICH)
control_rates AS (
  SELECT
    COUNT(*) AS n_control_admissions,
    ROUND(100.0 * SUM(abn_potassium) / COUNT(*), 2) AS ctrl_pct_abn_potassium,
    ROUND(100.0 * SUM(abn_sodium) / COUNT(*), 2) AS ctrl_pct_abn_sodium,
    ROUND(100.0 * SUM(abn_hemoglobin) / COUNT(*), 2) AS ctrl_pct_abn_hemoglobin,
    ROUND(100.0 * SUM(abn_platelets) / COUNT(*), 2) AS ctrl_pct_abn_platelets,
    ROUND(100.0 * SUM(abn_inr) / COUNT(*), 2) AS ctrl_pct_abn_inr,
    ROUND(100.0 * SUM(abn_creatinine) / COUNT(*), 2) AS ctrl_pct_abn_creatinine,
    ROUND(100.0 * SUM(abn_glucose) / COUNT(*), 2) AS ctrl_pct_abn_glucose
  FROM control_admissions
)

-- Final: combine case quintile stats with control rates for side-by-side comparison
SELECT
  cq.quintile,
  cq.n_admissions,
  cq.min_abn_count_in_quintile,
  cq.max_abn_count_in_quintile,
  cq.mortality_pct,
  cq.mean_los_days,
  -- case rates
  cq.pct_abn_potassium AS case_pct_abn_potassium,
  cq.pct_abn_sodium AS case_pct_abn_sodium,
  cq.pct_abn_hemoglobin AS case_pct_abn_hemoglobin,
  cq.pct_abn_platelets AS case_pct_abn_platelets,
  cq.pct_abn_inr AS case_pct_abn_inr,
  cq.pct_abn_creatinine AS case_pct_abn_creatinine,
  cq.pct_abn_glucose AS case_pct_abn_glucose,
  -- control rates (same for all rows; repeated for convenience)
  cr.n_control_admissions,
  cr.ctrl_pct_abn_potassium,
  cr.ctrl_pct_abn_sodium,
  cr.ctrl_pct_abn_hemoglobin,
  cr.ctrl_pct_abn_platelets,
  cr.ctrl_pct_abn_inr,
  cr.ctrl_pct_abn_creatinine,
  cr.ctrl_pct_abn_glucose
FROM case_quintile_stats cq
CROSS JOIN control_rates cr
ORDER BY cq.quintile;