WITH stroke_cohort AS (
  -- Identify stroke admissions for males aged 52-62 at admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- ICU flag: 1 if hadm_id had an ICU stay, else 0
    CASE WHEN (SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = a.hadm_id) > 0 THEN 1 ELSE 0 END AS icu_flag,
    p.anchor_age,
    p.anchor_year,
    -- Age at admission (approximate)
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm,
    -- LOS in days
    TIMESTAMP_DIFF(COALESCE(a.dischtime, a.admittime), a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE (LOWER(dd.long_title) LIKE '%stroke%' OR LOWER(dd.long_title) LIKE '%cerebrovascular%')
    AND LOWER(p.gender) IN ('m','male')
    AND (p.anchor_age IS NOT NULL)
    AND (p.anchor_year IS NOT NULL)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
),
stroke_cohort_final AS (
  SELECT
    sc.subject_id,
    sc.hadm_id,
    sc.admittime,
    sc.dischtime,
    sc.deathtime,
    sc.hospital_expire_flag,
    sc.icu_flag,
    sc.los_days,
    CASE WHEN sc.los_days <= 5 THEN '≤5' ELSE '>5' END AS los_cat,
    CASE WHEN sc.hospital_expire_flag = 1 OR sc.deathtime IS NOT NULL THEN 1 ELSE 0 END AS has_hosp_death
  FROM stroke_cohort sc
),
stroke_subjects AS (
  SELECT DISTINCT subject_id FROM stroke_cohort_final
),
-- Comorbidity burden per subject (within stroke subjects)
comorb_by_subject AS (
  SELECT ss.subject_id, COUNT(DISTINCT di.icd_code) AS comorb_count
  FROM stroke_subjects ss
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ss.subject_id = di.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY ss.subject_id
),
comorb_tertile AS (
  SELECT c.subject_id, c.comorb_count,
         NTILE(3) OVER (ORDER BY c.comorb_count ASC) AS comorb_tertile
  FROM comorb_by_subject c
),
-- CKD presence per subject (stroke subjects only)
ckd_presence AS (
  SELECT ss.subject_id,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%kidney%' OR LOWER(dd.long_title) LIKE '%renal%' THEN 1 ELSE 0 END) AS has_ckd
  FROM stroke_subjects ss
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ss.subject_id = di.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY ss.subject_id
),
-- Diabetes presence per subject (stroke subjects only)
diabetes_presence AS (
  SELECT ss.subject_id,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diab%' OR LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diab
  FROM stroke_subjects ss
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ss.subject_id = di.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY ss.subject_id
)

SELECT
  CAST(s.icu_flag AS INT64) AS icu_flag,          -- 1 = ICU, 0 = non-ICU
  s.los_cat,                                       -- '≤5' or '>5'
  t.comorb_tertile,                                 -- 1 (low) .. 3 (high)
  COUNT(DISTINCT s.subject_id) AS n_subjects,
  100.0 * SUM(CASE WHEN s.has_hosp_death = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT s.subject_id) AS in_hosp_mortality_pct,
  100.0 * SUM(CASE WHEN c.has_ckd = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT s.subject_id) AS ckd_prev_pct,
  100.0 * SUM(CASE WHEN d.has_diab = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT s.subject_id) AS diabetes_prev_pct
FROM (
  SELECT sf.subject_id, sf.hadm_id, sf.admittime, sf.dischtime, sf.deathtime, sf.icu_flag,
         sf.los_days, sf.los_cat, sf.has_hosp_death
  FROM stroke_cohort_final sf
) AS s
LEFT JOIN comorb_tertile t ON s.subject_id = t.subject_id
LEFT JOIN ckd_presence c ON s.subject_id = c.subject_id
LEFT JOIN diabetes_presence d ON s.subject_id = d.subject_id
GROUP BY icu_flag, los_cat, comorb_tertile
ORDER BY icu_flag, los_cat, comorb_tertile;