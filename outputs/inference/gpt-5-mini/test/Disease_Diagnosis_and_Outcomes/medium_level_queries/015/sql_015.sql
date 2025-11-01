WITH
-- female admissions for patients aged 48-58 (inclusive)
female_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),

-- admissions that include any diagnosis whose description suggests stroke
stroke_admissions AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE LOWER(COALESCE(d.long_title, '')) LIKE '%stroke%'
     OR LOWER(COALESCE(d.long_title, '')) LIKE '%cerebrovascular%'
),

-- comorbidity count per admission: distinct diagnosis codes excluding stroke-related diagnoses
comorbidity_counts AS (
  SELECT
    di.hadm_id,
    COUNT(DISTINCT IF(
      NOT (
        LOWER(COALESCE(d.long_title, '')) LIKE '%stroke%'
        OR LOWER(COALESCE(d.long_title, '')) LIKE '%cerebrovascular%'
      ),
      di.icd_code,
      NULL
    )) AS num_comorbid
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  GROUP BY di.hadm_id
),

-- build cohort: female, age 48-58, stroke admission, attach comorbidity count, ICU flag, LOS group
cohort AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime,
    fa.dischtime,
    fa.hospital_expire_flag,
    COALESCE(cc.num_comorbid, 0) AS num_comorbid,
    -- ICU flag: admission has at least one icustays row
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.hadm_id = fa.hadm_id
    ) THEN 'ICU' ELSE 'Non-ICU' END AS icu_flag,
    -- hospital LOS in days (date difference)
    CASE
      WHEN DATE_DIFF(CAST(fa.dischtime AS DATE), CAST(fa.admittime AS DATE), DAY) <= 5 THEN '≤5 days'
      ELSE '>5 days'
    END AS los_group
  FROM female_admissions fa
  JOIN stroke_admissions sa
    USING(hadm_id)
  LEFT JOIN comorbidity_counts cc
    USING(hadm_id)
)

-- final aggregation with mortality and 95% CI (Wald)
SELECT
  icu_flag,
  los_group,
  CASE
    WHEN num_comorbid <= 2 THEN 'Low (0-2)'
    WHEN num_comorbid BETWEEN 3 AND 5 THEN 'Medium (3-5)'
    ELSE 'High (>=6)'
  END AS comorbidity_group,
  COUNT(*) AS n_admissions,
  SUM(IF(hospital_expire_flag = 1, 1, 0)) AS deaths,
  ROUND(100 * SAFE_DIVIDE(SUM(IF(hospital_expire_flag = 1, 1, 0)), COUNT(*)), 2) AS mortality_percent,
  -- 95% CI using normal approximation (Wald); clipped to [0,100]
  ROUND(100 * GREATEST(
    0,
    SAFE_DIVIDE(SAFE_SUBTRACT(
      SAFE_DIVIDE(SUM(IF(hospital_expire_flag = 1, 1, 0)), COUNT(*)),
      1.96 * SQRT(
        SAFE_DIVIDE(SAFE_MULTIPLY(
          SAFE_DIVIDE(SUM(IF(hospital_expire_flag = 1, 1, 0)), COUNT(*)),
          SAFE_SUBTRACT(1, SAFE_DIVIDE(SUM(IF(hospital_expire_flag = 1, 1, 0)), COUNT(*)))
        ), COUNT(*))
      )
    ), 1) -- outer SAFE_DIVIDE with 1 to avoid div-by-zero; kept for symmetry
  ), 4) AS ci_lower_percent,
  ROUND(100 * LEAST(
    1,
    SAFE_DIVIDE(SAFE_ADD(
      SAFE_DIVIDE(SUM(IF(hospital_expire_flag = 1, 1, 0)), COUNT(*)),
      1.96 * SQRT(
        SAFE_DIVIDE(SAFE_MULTIPLY(
          SAFE_DIVIDE(SUM(IF(hospital_expire_flag = 1, 1, 0)), COUNT(*)),
          SAFE_SUBTRACT(1, SAFE_DIVIDE(SUM(IF(hospital_expire_flag = 1, 1, 0)), COUNT(*)))
        ), COUNT(*))
      )
    ), 1)
  ), 4) AS ci_upper_percent
FROM cohort
-- group by the nominal comorbidity group, but we need to group by num_comorbid bucket to preserve counts
GROUP BY icu_flag, los_group,
  CASE
    WHEN num_comorbid <= 2 THEN 'Low (0-2)'
    WHEN num_comorbid BETWEEN 3 AND 5 THEN 'Medium (3-5)'
    ELSE 'High (>=6)'
  END
HAVING COUNT(*) > 0
ORDER BY icu_flag, los_group, comorbidity_group;