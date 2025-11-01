WITH
-- HF cohort: male, age 44-54, HF (I50%) during hospital admission
hf_cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    CASE
      WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS in_hospital_death,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS LOS_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND di.icd_version = 10
    AND di.icd_code LIKE 'I50%'
),
-- ICU flag per admission: 1 if there is at least one ICU stay for this hadm_id
icu_flags AS (
  SELECT hadm_id, 1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
-- Approximate Charlson score per hadm_id (coarse, using a subset of comorbidities)
charlson AS (
  SELECT t.hadm_id, SUM(t.weight) AS ch_score
  FROM (
    SELECT di.hadm_id,
           CASE
             WHEN di.icd_version = 10 AND (di.icd_code LIKE 'I50%' OR di.icd_code LIKE 'I21%') THEN 1
             WHEN di.icd_version = 10 AND di.icd_code LIKE 'I60%' THEN 1
             WHEN di.icd_version = 10 AND di.icd_code LIKE 'N18%' THEN 1
             WHEN di.icd_version = 10 AND di.icd_code LIKE 'C%' THEN 1
             WHEN di.icd_version = 10 AND di.icd_code LIKE 'B20%' THEN 1
             WHEN di.icd_version = 10 AND di.icd_code LIKE 'J44%' THEN 1
             WHEN di.icd_version = 10 AND di.icd_code LIKE 'K70%' THEN 1
             WHEN di.icd_version = 10 AND di.icd_code LIKE 'C77%' THEN 1
             ELSE 0
           END AS weight
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id IN (SELECT hadm_id FROM hf_cohort)
  ) AS t
  GROUP BY t.hadm_id
),
-- MV detection: ICU chart events with labels indicating ventilation
mv_admissions AS (
  SELECT DISTINCT i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` i
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON i.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ventilator%' OR LOWER(di.label) LIKE '%ventilation%'
),
-- Vasopressor detection
vasop_admissions AS (
  SELECT DISTINCT i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` i
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON i.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%norepinephrine%' OR LOWER(di.label) LIKE '%epinephrine%'
     OR LOWER(di.label) LIKE '%dopamine%' OR LOWER(di.label) LIKE '%phenylephrine%' OR LOWER(di.label) LIKE '%vasopressor%'
),
-- Renal Replacement Therapy detection
rrt_admissions AS (
  SELECT DISTINCT i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` i
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON i.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%' OR LOWER(di.label) LIKE '%renal replacement%'
     OR LOWER(di.label) LIKE '%hemofiltration%' OR LOWER(di.label) LIKE '%crrt%'
)
SELECT
  COALESCE(i.icu_flag, 0) AS icu_flag,
  CASE WHEN h.LOS_days <= 7 THEN '<=7' ELSE '>7' END AS los_group,
  CASE
    WHEN c.ch_score IS NULL OR c.ch_score <= 1 THEN '0-1'
    WHEN c.ch_score = 2 THEN '2'
    ELSE '>=3'
  END AS charlson_group,
  COUNT(*) AS total,
  SUM(h.in_hospital_death) AS deaths,
  SUM(CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS mv_count,
  SUM(CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS vasop_count,
  SUM(CASE WHEN rrtd.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS rrt_count,
  -- Mortality prevalence with 95% CI (approx.)
  100 * (SAFE_DIVIDE(SUM(h.in_hospital_death), COUNT(*))) AS mortality_pct,
  100 * (SAFE_DIVIDE(SUM(h.in_hospital_death), COUNT(*)) -
         1.96 * SQRT(
           SAFE_DIVIDE(SUM(h.in_hospital_death), COUNT(*)) *
           (1 - SAFE_DIVIDE(SUM(h.in_hospital_death), COUNT(*))) /
           NULLIF(COUNT(*), 0)
         )) AS mortality_ci_lower,
  100 * (SAFE_DIVIDE(SUM(h.in_hospital_death), COUNT(*)) +
         1.96 * SQRT(
           SAFE_DIVIDE(SUM(h.in_hospital_death), COUNT(*)) *
           (1 - SAFE_DIVIDE(SUM(h.in_hospital_death), COUNT(*))) /
           NULLIF(COUNT(*), 0)
         )) AS mortality_ci_upper,
  -- MV prevalence and its CI
  100 * (SAFE_DIVIDE(SUM(CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*))) AS mv_pct,
  100 * (SAFE_DIVIDE(SUM(CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) -
         1.96 * SQRT(
           SAFE_DIVIDE(SUM(CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) *
           (1 - SAFE_DIVIDE(SUM(CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*))) /
           NULLIF(COUNT(*), 0)
         )) AS mv_ci_lower,
  100 * (SAFE_DIVIDE(SUM(CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) +
         1.96 * SQRT(
           SAFE_DIVIDE(SUM(CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) *
           (1 - SAFE_DIVIDE(SUM(CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*))) /
           NULLIF(COUNT(*), 0)
         )) AS mv_ci_upper,
  -- Vasopressor prevalence and its CI
  100 * (SAFE_DIVIDE(SUM(CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*))) AS vasop_pct,
  100 * (SAFE_DIVIDE(SUM(CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) -
         1.96 * SQRT(
           SAFE_DIVIDE(SUM(CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) *
           (1 - SAFE_DIVIDE(SUM(CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*))) /
           NULLIF(COUNT(*), 0)
         )) AS vasop_ci_lower,
  100 * (SAFE_DIVIDE(SUM(CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) +
         1.96 * SQRT(
           SAFE_DIVIDE(SUM(CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) *
           (1 - SAFE_DIVIDE(SUM(CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*))) /
           NULLIF(COUNT(*), 0)
         )) AS vasop_ci_upper,
  -- RRT prevalence and its CI
  100 * (SAFE_DIVIDE(SUM(CASE WHEN rrtd.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*))) AS rrt_pct,
  100 * (SAFE_DIVIDE(SUM(CASE WHEN rrtd.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) -
         1.96 * SQRT(
           SAFE_DIVIDE(SUM(CASE WHEN rrtd.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) *
           (1 - SAFE_DIVIDE(SUM(CASE WHEN rrtd.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*))) /
           NULLIF(COUNT(*), 0)
         )) AS rrt_ci_lower,
  100 * (SAFE_DIVIDE(SUM(CASE WHEN rrtd.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) +
         1.96 * SQRT(
           SAFE_DIVIDE(SUM(CASE WHEN rrtd.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) *
           (1 - SAFE_DIVIDE(SUM(CASE WHEN rrtd.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*))) /
           NULLIF(COUNT(*), 0)
         )) AS rrt_ci_upper
FROM hf_cohort h
LEFT JOIN icu_flags i
  ON h.hadm_id = i.hadm_id
LEFT JOIN charlson c
  ON h.hadm_id = c.hadm_id
LEFT JOIN mv_admissions mv
  ON h.hadm_id = mv.hadm_id
LEFT JOIN vasop_admissions vp
  ON h.hadm_id = vp.hadm_id
LEFT JOIN rrt_admissions rrtd
  ON h.hadm_id = rrtd.hadm_id
GROUP BY icu_flag, los_group, charlson_group
ORDER BY icu_flag, los_group, charlson_group;