WITH diagnoses_by_adm AS (
  SELECT
    di.hadm_id,
    di.subject_id,
    di.icd_code,
    di.icd_version,
    LOWER(dd.long_title) AS long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
),
stroke_admissions AS (
  -- Select stroke admissions for female patients aged 48-58 at admission
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN diagnoses_by_adm AS dba
    ON a.hadm_id = dba.hadm_id
   AND a.subject_id = dba.subject_id
  WHERE LOWER(p.gender) IN ('f','female')
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 48 AND 58
    AND (dba.long_title LIKE '%stroke%' OR dba.long_title LIKE '%cerebrovascular%')
),
icu_presence AS (
  -- ICU exposure per admission (ICU stays exist or not for the admission)
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
comorb_by_adm AS (
  -- Per-admission comorbidity flags derived from stroke-admission diagnoses
  SELECT
    hadm_id,
    MAX(CASE WHEN long_title LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN long_title LIKE '%hypertension%' THEN 1 ELSE 0 END) AS has_hypertension,
    MAX(CASE WHEN long_title LIKE '%heart failure%' OR long_title LIKE '%congestive heart failure%' THEN 1 ELSE 0 END) AS has_chf,
    MAX(CASE WHEN long_title LIKE '%cerebrovascular%' OR long_title LIKE '%stroke%' THEN 1 ELSE 0 END) AS has_cv,
    MAX(CASE WHEN long_title LIKE '%renal%' OR long_title LIKE '%kidney%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN long_title LIKE '%liver%' THEN 1 ELSE 0 END) AS has_liver,
    MAX(CASE WHEN long_title LIKE '%cancer%' OR long_title LIKE '%carcinoma%' THEN 1 ELSE 0 END) AS has_malignancy,
    MAX(CASE WHEN long_title LIKE '%pulmonary%' OR long_title LIKE '%copd%' THEN 1 ELSE 0 END) AS has_pulm,
    MAX(CASE WHEN long_title LIKE '%immun%' THEN 1 ELSE 0 END) AS has_immuno
  FROM diagnoses_by_adm
  GROUP BY hadm_id
),
stroke_with_burden AS (
  -- Combine stroke admissions with ICU exposure and comorbidity burden
  SELECT
    s.hadm_id,
    s.subject_id,
    s.admittime,
    s.dischtime,
    s.deathtime,
    TIMESTAMP_DIFF(s.dischtime, s.admittime, DAY) AS los_days,
    CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag, -- 1 if ICU exposure, else 0
    (COALESCE(c.has_diabetes, 0) + COALESCE(c.has_hypertension, 0) + COALESCE(c.has_chf, 0)
     + COALESCE(c.has_cv, 0) + COALESCE(c.has_ckd, 0) + COALESCE(c.has_liver, 0)
     + COALESCE(c.has_malignancy, 0) + COALESCE(c.has_pulm, 0) + COALESCE(c.has_immuno, 0)
    ) AS comorbidity_burden,
    CASE WHEN s.deathtime IS NOT NULL THEN 1 ELSE 0 END AS death_flag
  FROM stroke_admissions AS s
  LEFT JOIN icu_presence AS i
    ON i.hadm_id = s.hadm_id
  LEFT JOIN comorb_by_adm AS c
    ON c.hadm_id = s.hadm_id
)
-- Final grouping by ICU exposure, LOS bucket, and comorbidity burden
, grouped AS (
  SELECT
    icu_flag AS icu_flag,
    CASE WHEN los_days <= 5 THEN '≤5' ELSE '>5' END AS los_group,
    comorbidity_burden AS comorbidity_burden,
    COUNT(*) AS total,
    SUM(death_flag) AS deaths
  FROM stroke_with_burden
  GROUP BY icu_flag, los_group, comorbidity_burden
  ORDER BY icu_flag, los_group, comorbidity_burden
)
SELECT
  g.icu_flag,
  g.los_group,
  g.comorbidity_burden,
  g.total,
  g.deaths,
  SAFE_DIVIDE(g.deaths, g.total) AS mortality_rate,
  -- Wilson score 95% CI
  (SAFE_DIVIDE(g.deaths, g.total)
     + 3.841470976/(2*g.total)
     - 1.959963984540054 * SQRT( SAFE_DIVIDE(g.deaths, g.total) * (1 - SAFE_DIVIDE(g.deaths, g.total)) / g.total
                          + 3.841470976/(4*g.total*g.total) )
  ) / (1 + 3.841470976/g.total) AS lower_ci,
  (SAFE_DIVIDE(g.deaths, g.total)
     + 3.841470976/(2*g.total)
     + 1.959963984540054 * SQRT( SAFE_DIVIDE(g.deaths, g.total) * (1 - SAFE_DIVIDE(g.deaths, g.total)) / g.total
                          + 3.841470976/(4*g.total*g.total) )
  ) / (1 + 3.841470976/g.total) AS upper_ci
FROM grouped g
ORDER BY g.icu_flag, g.los_group, g.comorbidity_burden;