WITH postop_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%postoperative%'
),

-- Charlson-like comorbidity flags per hadm_id (approximate, counts major categories)
comorb AS (
  SELECT hadm_id,
         MAX(CASE WHEN icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS ckd,
         MAX(CASE WHEN icd_code LIKE 'E1%'  THEN 1 ELSE 0 END) AS diabetes,
         MAX(CASE WHEN icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS chf,
         MAX(CASE WHEN icd_code LIKE 'I6%'  THEN 1 ELSE 0 END) AS cvd,
         MAX(CASE WHEN icd_code LIKE 'C%'   THEN 1 ELSE 0 END) AS cancer,
         MAX(CASE WHEN icd_code LIKE 'J4%'  THEN 1 ELSE 0 END) AS copd,
         MAX(CASE WHEN icd_code LIKE 'K70%' THEN 1 ELSE 0 END) AS liver,
         MAX(CASE WHEN icd_code LIKE 'F0%'  THEN 1 ELSE 0 END) AS dementia
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  GROUP BY hadm_id
),

-- Base cohort: age 51-61 male admissions with postoperative complications
base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_icu,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON icu.subject_id = a.subject_id AND icu.hadm_id = a.hadm_id
  WHERE p.gender IN ('M','Male')
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 51 AND 61
    AND a.hadm_id IN (SELECT hadm_id FROM postop_hadm)
),

-- Compute LOS days per admission
cohort AS (
  SELECT
    b.*,
    -- LOS in days: end date is discharge or death; add 1 to count admission day
    DATE_DIFF(DATE(COALESCE(b.dischtime, b.deathtime, b.admittime)), DATE(b.admittime), DAY) + 1 AS los_days
  FROM base AS b
),

-- Attach comorbidity flags per hadm_id
cohort_with_comorb AS (
  SELECT
    c.*,
    COALESCE(co.ckd, 0) AS ckd,
    COALESCE(co.diabetes, 0) AS diabetes,
    COALESCE(co.chf, 0) AS chf,
    COALESCE(co.cvd, 0) AS cvd,
    COALESCE(co.cancer, 0) AS cancer,
    COALESCE(co.copd, 0) AS copd,
    COALESCE(co.liver, 0) AS liver,
    COALESCE(co.dementia, 0) AS dementia,
    (COALESCE(co.ckd,0) + COALESCE(co.diabetes,0) + COALESCE(co.chf,0) + COALESCE(co.cvd,0)
     + COALESCE(co.cancer,0) + COALESCE(co.copd,0) + COALESCE(co.liver,0) + COALESCE(co.dementia,0)) AS comorb_sum
  FROM cohort AS c
  LEFT JOIN comorb AS co
    ON co.hadm_id = c.hadm_id
),

final AS (
  SELECT
    CASE WHEN is_icu = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_group,
    CASE
      WHEN los_days BETWEEN 1 AND 2 THEN '1-2'
      WHEN los_days BETWEEN 3 AND 5 THEN '3-5'
      WHEN los_days BETWEEN 6 AND 9 THEN '6-9'
      WHEN los_days >= 10 THEN '>=10'
    END AS LOS_category,
    CASE
      WHEN comorb_sum <= 1 THEN '0-1'
      WHEN comorb_sum = 2 THEN '2'
      ELSE '>=3'
    END AS charlson_group,
    CASE WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality,
    los_days,
    ckd,
    diabetes
  FROM cohort_with_comorb
  WHERE los_days IS NOT NULL
)

SELECT
  icu_group,
  LOS_category,
  charlson_group,
  100.0 * SUM(mortality) / COUNT(*) AS mortality_percent,
  MEDIAN(los_days) AS median_los,
  100.0 * SUM(ckd) / COUNT(*) AS ckd_prevalence,
  100.0 * SUM(diabetes) / COUNT(*) AS diabetes_prevalence
FROM final
GROUP BY icu_group, LOS_category, charlson_group
ORDER BY icu_group, LOS_category, charlson_group;