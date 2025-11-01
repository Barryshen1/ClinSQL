WITH stroke_codes AS (
  SELECT
    hadm_id,
    -- Ischemic codes: ICD-9 433.x, 434.x, 436; ICD-10 I63.x
    MAX(CASE
          WHEN icd_version = 9 AND (icd_code LIKE '433%' OR icd_code LIKE '434%' OR icd_code LIKE '436%')
            THEN 1 ELSE 0 END) AS ischemic_9,
    MAX(CASE
          WHEN icd_version = 9 AND (icd_code LIKE '431%' OR icd_code LIKE '430%' OR icd_code LIKE '432%')
            THEN 1 ELSE 0 END) AS hemorrhagic_9,
    MAX(CASE
          WHEN icd_version = 10 AND (icd_code LIKE 'I63%')
            THEN 1 ELSE 0 END) AS ischemic_10,
    MAX(CASE
          WHEN icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%')
            THEN 1 ELSE 0 END) AS hemorrhagic_10
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

stroke_flags AS (
  SELECT
    hadm_id,
    GREATEST(ischemic_9, ischemic_10) AS has_ischemic,
    GREATEST(hemorrhagic_9, hemorrhagic_10) AS has_hemorrhagic
  FROM stroke_codes
),

-- Derive stroke_type per admission
stroke_type AS (
  SELECT
    hadm_id,
    CASE
      WHEN has_ischemic = 1 AND has_hemorrhagic = 0 THEN 'Ischemic'
      WHEN has_hemorrhagic = 1 AND has_ischemic = 0 THEN 'Hemorrhagic'
      WHEN has_ischemic = 1 AND has_hemorrhagic = 1 THEN 'Ischemic' -- prefer ischemic if both present
      ELSE NULL
    END AS stroke_type
  FROM stroke_flags
  WHERE has_ischemic = 1 OR has_hemorrhagic = 1
),

-- Comorbidity flags by ICD code long titles (approximate Elixhauser-style groups)
diag_long AS (
  SELECT d.hadm_id,
         LOWER(ld.long_title) AS long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ld
    ON d.icd_code = ld.icd_code
   AND d.icd_version = ld.icd_version
),

comorb_flags AS (
  SELECT hadm_id,
         MAX(CASE WHEN REGEXP_CONTAINS(long_title, r'diabetes') THEN 1 ELSE 0 END) AS c_diabetes,
         MAX(CASE WHEN REGEXP_CONTAINS(long_title, r'renal|kidney') THEN 1 ELSE 0 END) AS c_renal,
         MAX(CASE WHEN REGEXP_CONTAINS(long_title, r'liver') THEN 1 ELSE 0 END) AS c_liver,
         MAX(CASE WHEN REGEXP_CONTAINS(long_title, r'cancer|neoplasm') THEN 1 ELSE 0 END) AS c_cancer,
         MAX(CASE WHEN REGEXP_CONTAINS(long_title, r'heart failure|congestive heart failure') THEN 1 ELSE 0 END) AS c_heartfailure,
         MAX(CASE WHEN REGEXP_CONTAINS(long_title, r'hypertension') THEN 1 ELSE 0 END) AS c_hypertension,
         MAX(CASE WHEN REGEXP_CONTAINS(long_title, r'copd|chronic obstructive pulmonary disease') THEN 1 ELSE 0 END) AS c_copd
  FROM diag_long
  GROUP BY hadm_id
),

comorb_total AS (
  SELECT hadm_id,
         COALESCE(c_diabetes,0)
       + COALESCE(c_renal,0)
       + COALESCE(c_liver,0)
       + COALESCE(c_cancer,0)
       + COALESCE(c_heartfailure,0)
       + COALESCE(c_hypertension,0)
       + COALESCE(c_copd,0) AS comorb_count
  FROM comorb_flags
),

-- Base cohort: male patients aged 44-54 with a stroke admission
base_cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    s.stroke_type,
    COALESCE(ct.comorb_count, 0) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN stroke_type s
    ON s.hadm_id = a.hadm_id
  LEFT JOIN comorb_total ct
    ON ct.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND s.stroke_type IS NOT NULL
),

-- Compute LOS (in days) and strata
cohort_with_groups AS (
  SELECT
    b.*,
    DATE_DIFF(DATE(b.dischtime), DATE(b.admittime), DAY) AS los_days,
    CASE WHEN DATE_DIFF(DATE(b.dischtime), DATE(b.admittime), DAY) <= 5 THEN '<=5' ELSE '>5' END AS los_group,
    CASE
      WHEN COALESCE(b.comorb_count,0) = 0 THEN 'low'
      WHEN COALESCE(b.comorb_count,0) BETWEEN 1 AND 2 THEN 'med'
      WHEN COALESCE(b.comorb_count,0) >= 3 THEN 'high'
    END AS comorb_group
  FROM base_cohort b
),

-- Mechanical ventilation indicator per hadm_id (ICU-level events mapped to hospital hadm_id)
vent_flags AS (
  SELECT pe.hadm_id,
         MAX(CASE WHEN REGEXP_CONTAINS(LOWER(di.label), '(ventilator|ventilation)') THEN 1 ELSE 0 END) AS has_vent
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = pe.itemid
  GROUP BY pe.hadm_id
),

-- Vasopressor usage indicator
vasop_flags AS (
  SELECT pe.hadm_id,
         MAX(CASE WHEN REGEXP_CONTAINS(LOWER(di.label), '(norepinephrine|epinephrine|dopamine|vasopressor|pressor)') THEN 1 ELSE 0 END) AS has_vaso
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = pe.itemid
  GROUP BY pe.hadm_id
),

-- Renal replacement therapy (RRT) indicator
rrt_flags AS (
  SELECT pe.hadm_id,
         MAX(CASE WHEN REGEXP_CONTAINS(LOWER(di.label), '(renal replacement|dialysis|crrt|hemofiltration)') THEN 1 ELSE 0 END) AS has_rrt
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = pe.itemid
  GROUP BY pe.hadm_id
),

-- Median LOS per group via array-agg approach
medians AS (
  SELECT
    cw.stroke_type AS stroke_type,
    cw.los_group AS los_group,
    cw.comorb_group AS comorb_group,
    ARRAY_AGG(cw.los_days ORDER BY cw.los_days) AS los_arr
  FROM cohort_with_groups cw
  GROUP BY cw.stroke_type, cw.los_group, cw.comorb_group
),

median_values AS (
  SELECT
    m.stroke_type,
    m.los_group,
    m.comorb_group,
    los_arr[OFFSET(FLOOR((CAST(ARRAY_LENGTH(los_arr) AS INT64) - 1) / 2))] AS median_los_days
  FROM medians m
)

-- Final aggregated results by stroke_type, LOS group, and comorbidity group
SELECT
  a.stroke_type,
  a.los_group,
  a.comorb_group,
  a.n_pats,
  100.0 * a.n_deaths / NULLIF(a.n_pats, 0) AS mortality_percent,
  mv.median_los_days AS median_los_days,
  100.0 * a.n_vent / NULLIF(a.n_pats, 0) AS pct_mech_vent,
  100.0 * a.n_vasop / NULLIF(a.n_pats, 0) AS pct_vasopressors,
  100.0 * a.n_rrt / NULLIF(a.n_pats, 0) AS pct_rrt
FROM (
  SELECT
    cw.stroke_type,
    cw.los_group,
    cw.comorb_group,
    COUNT(*) AS n_pats,
    SUM(CASE WHEN (cw.deathtime IS NOT NULL OR cw.hospital_expire_flag = 1) THEN 1 ELSE 0 END) AS n_deaths,
    SUM(vf.has_vent) AS n_vent,
    SUM(vas.has_vaso) AS n_vasop,
    SUM(rf.has_rrt) AS n_rrt
  FROM cohort_with_groups cw
  LEFT JOIN vent_flags vf ON vf.hadm_id = cw.hadm_id
  LEFT JOIN vasop_flags vas ON vas.hadm_id = cw.hadm_id
  LEFT JOIN rrt_flags rf ON rf.hadm_id = cw.hadm_id
  GROUP BY cw.stroke_type, cw.los_group, cw.comorb_group
) AS a
LEFT JOIN median_values mv
  ON mv.stroke_type = a.stroke_type
 AND mv.los_group = a.los_group
 AND mv.comorb_group = a.comorb_group
ORDER BY a.stroke_type, a.los_group, a.comorb_group;