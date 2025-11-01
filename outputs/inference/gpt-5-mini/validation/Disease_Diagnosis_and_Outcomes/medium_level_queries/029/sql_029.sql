WITH
-- 1) Diagnosis text per admission (use the hosp diagnosis tables)
diag_text AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    LOWER(dic.long_title) AS diag_text
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON di.icd_code = dic.icd_code
),

-- 2) Per-admission flags for sepsis / septic shock and Charlson comorbidity components
adm_flags AS (
  SELECT
    dt.hadm_id,
    MAX(CASE WHEN dt.diag_text LIKE '%septic shock%' THEN 1 ELSE 0 END) AS flag_septic_shock,
    MAX(CASE WHEN dt.diag_text LIKE '%sepsis%' OR dt.diag_text LIKE '%septicemia%' THEN 1 ELSE 0 END) AS flag_any_sepsis,

    -- Charlson components (keyword heuristics)
    MAX(CASE WHEN dt.diag_text LIKE '%myocardial%' OR dt.diag_text LIKE '%ischemi%' THEN 1 ELSE 0 END) AS c_mi,
    MAX(CASE WHEN dt.diag_text LIKE '%congestive heart failure%' OR dt.diag_text LIKE '%heart failure%' THEN 1 ELSE 0 END) AS c_chf,
    MAX(CASE WHEN dt.diag_text LIKE '%peripheral vascular%' OR dt.diag_text LIKE '%peripheral artery%' OR dt.diag_text LIKE '%arteriosclero%' THEN 1 ELSE 0 END) AS c_pvd,
    MAX(CASE WHEN dt.diag_text LIKE '%cerebrovascular%' OR dt.diag_text LIKE '%cva%' OR dt.diag_text LIKE '%stroke%' OR dt.diag_text LIKE '%cerebral infarct%' THEN 1 ELSE 0 END) AS c_cva,
    MAX(CASE WHEN dt.diag_text LIKE '%dementia%' THEN 1 ELSE 0 END) AS c_dementia,
    MAX(CASE WHEN dt.diag_text LIKE '%chronic obstructive pulmonary%' OR dt.diag_text LIKE '%emphysema%' OR dt.diag_text LIKE '%chronic bronchitis%' THEN 1 ELSE 0 END) AS c_copd,
    MAX(CASE WHEN dt.diag_text LIKE '%rheumatic%' THEN 1 ELSE 0 END) AS c_rheumatic,
    MAX(CASE WHEN dt.diag_text LIKE '%peptic ulcer%' OR dt.diag_text LIKE '%peptic ulcer disease%' THEN 1 ELSE 0 END) AS c_pud,

    -- Liver: detect moderate/severe first (higher weight), otherwise mild
    MAX(CASE WHEN dt.diag_text LIKE '%cirrhosis%' OR dt.diag_text LIKE '%portal hypertension%' OR dt.diag_text LIKE '%esophageal varices%' OR dt.diag_text LIKE '%hepatic failure%' THEN 1 ELSE 0 END) AS c_liver_severe,
    MAX(CASE WHEN (dt.diag_text LIKE '%chronic hepatitis%' OR dt.diag_text LIKE '%chronic liver%' OR dt.diag_text LIKE '%fatty liver%') AND NOT (dt.diag_text LIKE '%cirrhosis%' OR dt.diag_text LIKE '%portal hypertension%' OR dt.diag_text LIKE '%hepatic failure%') THEN 1 ELSE 0 END) AS c_liver_mild,

    -- Diabetes: detect with complications (higher weight) vs without
    MAX(CASE WHEN dt.diag_text LIKE '%diabetes%' AND (
                dt.diag_text LIKE '%with%' OR dt.diag_text LIKE '%complication%' OR dt.diag_text LIKE '%nephropathy%' OR dt.diag_text LIKE '%retinopathy%' OR dt.diag_text LIKE '%neuropathy%' OR dt.diag_text LIKE '%ketoacidosis%' OR dt.diag_text LIKE '%diabetic nephropathy%' )
             THEN 1 ELSE 0 END) AS c_dm_comp,
    MAX(CASE WHEN dt.diag_text LIKE '%diabetes%' AND NOT (
                dt.diag_text LIKE '%with%' OR dt.diag_text LIKE '%complication%' OR dt.diag_text LIKE '%nephropathy%' OR dt.diag_text LIKE '%retinopathy%' OR dt.diag_text LIKE '%neuropathy%' OR dt.diag_text LIKE '%ketoacidosis%' OR dt.diag_text LIKE '%diabetic nephropathy%' )
             THEN 1 ELSE 0 END) AS c_dm_nocomp,

    MAX(CASE WHEN dt.diag_text LIKE '%hemiplegia%' OR dt.diag_text LIKE '%paraplegia%' THEN 1 ELSE 0 END) AS c_hemiplegia,
    MAX(CASE WHEN dt.diag_text LIKE '%chronic kidney%' OR dt.diag_text LIKE '%chronic renal%' OR dt.diag_text LIKE '%end stage renal%' OR dt.diag_text LIKE '%end-stage renal%' OR dt.diag_text LIKE '%renal failure%' THEN 1 ELSE 0 END) AS c_renal,
    MAX(CASE WHEN (dt.diag_text LIKE '%secondary malignant%' OR dt.diag_text LIKE '%metastatic%' OR dt.diag_text LIKE '%metastasis%') THEN 1 ELSE 0 END) AS c_metastatic,
    MAX(CASE WHEN (dt.diag_text LIKE '%malignant%' OR dt.diag_text LIKE '%carcinoma%' OR dt.diag_text LIKE '%neoplasm%' OR dt.diag_text LIKE '%lymphoma%' OR dt.diag_text LIKE '%leukemia%') AND NOT (dt.diag_text LIKE '%secondary malignant%' OR dt.diag_text LIKE '%metastatic%' OR dt.diag_text LIKE '%metastasis%') THEN 1 ELSE 0 END) AS c_any_malignancy,
    MAX(CASE WHEN dt.diag_text LIKE '%hiv%' OR dt.diag_text LIKE '%aids%' THEN 1 ELSE 0 END) AS c_hiv

  FROM diag_text dt
  GROUP BY dt.hadm_id
),

-- 3) Compute Charlson score per admission by applying standard weights (heuristic mapping)
charlson_score AS (
  SELECT
    hadm_id,

    -- weights:
    -- MI 1, CHF 1, PVD 1, CVD 1, Dementia 1, COPD 1, Rheumatic 1, PUD 1,
    -- Mild liver 1, DM without comp 1, DM with comp 2, Hemiplegia 2, Renal 2,
    -- Any malignancy 2, Moderate/Severe liver 3, Metastatic 6, AIDS/HIV 6
    COALESCE(
      (c_mi * 1) +
      (c_chf * 1) +
      (c_pvd * 1) +
      (c_cva * 1) +
      (c_dementia * 1) +
      (c_copd * 1) +
      (c_rheumatic * 1) +
      (c_pud * 1) +
      (c_liver_mild * 1) +
      -- choose the higher liver weight if severe present
      (c_liver_severe * 3) +
      -- diabetes: if complication present use 2, else if only non-comp use 1
      (CASE WHEN c_dm_comp = 1 THEN 2 WHEN c_dm_nocomp = 1 THEN 1 ELSE 0 END) +
      (c_hemiplegia * 2) +
      (c_renal * 2) +
      (c_any_malignancy * 2) +
      (c_metastatic * 6) +
      (c_hiv * 6)
    , 0) AS charlson_score

  FROM adm_flags
),

-- 4) Admissions of interest: join admissions + patients + flags + charlson, restrict to females age 57-67 and to admissions with sepsis diagnoses
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- hospital LOS in days (integer)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN '<=7'
      ELSE '>7'
    END AS los_group,
    -- charlson grouped as <=3, 4-5, >5
    CASE
      WHEN cs.charlson_score <= 3 THEN '<=3'
      WHEN cs.charlson_score BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_group,
    -- sepsis classification: if any septic_shock diagnosis then septic_shock else if any sepsis/septicemia then sepsis_no_shock; else NULL
    CASE
      WHEN af.flag_septic_shock = 1 THEN 'septic_shock'
      WHEN af.flag_any_sepsis = 1 THEN 'sepsis_no_shock'
      ELSE NULL
    END AS sepsis_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN adm_flags af
    ON a.hadm_id = af.hadm_id
  LEFT JOIN charlson_score cs
    ON a.hadm_id = cs.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.dischtime IS NOT NULL
    -- only include admissions with sepsis (either sepsis without shock or septic shock)
    AND (af.flag_any_sepsis = 1 OR af.flag_septic_shock = 1)
),

-- 5) Aggregate mortality metrics stratified by LOS and Charlson, separately for sepsis_no_shock and septic_shock
agg AS (
  SELECT
    los_group,
    charlson_group,
    sepsis_type,
    COUNT(DISTINCT hadm_id) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    100.0 * SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(DISTINCT hadm_id)) AS mortality_pct
  FROM cohort
  GROUP BY los_group, charlson_group, sepsis_type
)

-- 6) Pivot/separate the two sepsis types to compute absolute and relative differences
SELECT
  COALESCE(a.los_group, b.los_group) AS los_group,
  COALESCE(a.charlson_group, b.charlson_group) AS charlson_group,

  -- No-shock (baseline) metrics
  COALESCE(a.n_admissions, 0) AS n_sepsis_no_shock,
  COALESCE(a.n_deaths, 0) AS deaths_sepsis_no_shock,
  ROUND(COALESCE(a.mortality_pct, 0), 2) AS mortality_pct_sepsis_no_shock,

  -- Septic shock metrics
  COALESCE(b.n_admissions, 0) AS n_septic_shock,
  COALESCE(b.n_deaths, 0) AS deaths_septic_shock,
  ROUND(COALESCE(b.mortality_pct, 0), 2) AS mortality_pct_septic_shock,

  -- Absolute difference (percentage points) and relative difference (ratio)
  ROUND(COALESCE(b.mortality_pct, 0) - COALESCE(a.mortality_pct, 0), 2) AS absolute_pct_point_diff_shock_minus_no_shock,
  CASE
    WHEN COALESCE(a.mortality_pct, 0) > 0
      THEN ROUND(COALESCE(b.mortality_pct, 0) / COALESCE(a.mortality_pct, 0), 2)
    ELSE NULL
  END AS relative_ratio_shock_over_no_shock

FROM
  -- left = sepsis without shock, right = septic shock
  (SELECT los_group, charlson_group, n_admissions, n_deaths, mortality_pct FROM agg WHERE sepsis_type = 'sepsis_no_shock') a
FULL OUTER JOIN
  (SELECT los_group, charlson_group, n_admissions, n_deaths, mortality_pct FROM agg WHERE sepsis_type = 'septic_shock') b
ON a.los_group = b.los_group AND a.charlson_group = b.charlson_group

ORDER BY
  los_group,
  CASE charlson_group WHEN '<=3' THEN 1 WHEN '4-5' THEN 2 WHEN '>5' THEN 3 ELSE 4 END;