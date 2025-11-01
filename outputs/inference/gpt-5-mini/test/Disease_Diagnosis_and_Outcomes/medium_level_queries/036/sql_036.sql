WITH eligible_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

hf_adms AS (
  -- admissions (hadm_id) among eligible_adms that have a heart failure diagnosis
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE di.hadm_id IN (SELECT hadm_id FROM eligible_adms)
    AND LOWER(COALESCE(dd.long_title, '')) LIKE '%heart fail%'
),

comorbids AS (
  -- For each HF admission, compute:
  --  - comorbidity_count = distinct diagnosis codes excluding heart failure diagnoses
  --  - flags for diabetes and CKD presence (based on diagnosis long_title patterns)
  SELECT
    di.hadm_id,
    COUNT(DISTINCT CASE WHEN LOWER(COALESCE(dd.long_title, '')) NOT LIKE '%heart fail%' THEN di.icd_code ELSE NULL END) AS comorbidity_count,
    MAX(CASE WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS diabetes_flag,
    MAX(CASE WHEN (
         LOWER(COALESCE(dd.long_title, '')) LIKE '%chronic kidney%' OR
         LOWER(COALESCE(dd.long_title, '')) LIKE '%kidney disease%' OR
         LOWER(COALESCE(dd.long_title, '')) LIKE '%renal failure%' OR
         LOWER(COALESCE(dd.long_title, '')) LIKE '%end stage renal%' OR
         LOWER(COALESCE(dd.long_title, '')) LIKE '%ckd%'
       ) THEN 1 ELSE 0 END) AS ckd_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE di.hadm_id IN (SELECT hadm_id FROM hf_adms)
  GROUP BY di.hadm_id
),

base AS (
  -- Join admissions, comorbidity info and compute LOS group
  SELECT
    e.hadm_id,
    e.subject_id,
    e.admittime,
    e.dischtime,
    e.hospital_expire_flag,
    COALESCE(c.comorbidity_count, 0) AS comorbidity_count,
    COALESCE(c.ckd_flag, 0) AS ckd_flag,
    COALESCE(c.diabetes_flag, 0) AS diabetes_flag,
    -- LOS in days (integer); <=5 vs >5
    TIMESTAMP_DIFF(e.dischtime, e.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(e.dischtime, e.admittime, DAY) <= 5 THEN '<=5'
      ELSE '>5'
    END AS los_group
  FROM eligible_adms e
  JOIN hf_adms h
    ON e.hadm_id = h.hadm_id
  LEFT JOIN comorbids c
    ON e.hadm_id = c.hadm_id
),

quantiles AS (
  -- approximate tertile cutpoints for comorbidity_count across the cohort
  SELECT
    APPROX_QUANTILES(comorbidity_count, 3) AS qs
  FROM base
),

base_with_tert AS (
  -- assign Low/Med/High tertile per admission using the computed cutpoints
  SELECT
    b.*,
    CASE
      WHEN b.comorbidity_count <= q.qs[OFFSET(1)] THEN 'Low'
      WHEN b.comorbidity_count <= q.qs[OFFSET(2)] THEN 'Med'
      ELSE 'High'
    END AS comorbidity_tertile
  FROM base b
  CROSS JOIN quantiles q
)

-- Final aggregation: by comorbidity tertile and LOS group
SELECT
  comorbidity_tertile,
  los_group,
  COUNT(*) AS N_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)), 1) AS mortality_pct,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN ckd_flag = 1 THEN 1 ELSE 0 END), COUNT(*)), 1) AS ckd_pct,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN diabetes_flag = 1 THEN 1 ELSE 0 END), COUNT(*)), 1) AS diabetes_pct
FROM base_with_tert
GROUP BY comorbidity_tertile, los_group
ORDER BY
  -- order tertiles Low -> Med -> High
  CASE comorbidity_tertile WHEN 'Low' THEN 1 WHEN 'Med' THEN 2 WHEN 'High' THEN 3 ELSE 4 END,
  los_group;