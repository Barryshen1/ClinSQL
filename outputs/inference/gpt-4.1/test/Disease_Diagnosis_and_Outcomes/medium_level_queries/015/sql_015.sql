WITH stroke_codes AS (
  -- ICD-9 and ICD-10 codes for stroke
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10: I60-I64
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I6[0-4]'))
    -- ICD-9: 430-434, 436
    OR (icd_version = 9 AND (REGEXP_CONTAINS(icd_code, r'^43[0-4]') OR icd_code = '436'))
),
stroke_admissions AS (
  -- Admissions with stroke diagnosis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN stroke_codes sc
    ON d.icd_code = sc.icd_code AND d.icd_version = sc.icd_version
),
female_stroke_admissions AS (
  -- Add age and gender filters
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM stroke_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON sa.subject_id = a.subject_id AND sa.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
icu_status AS (
  -- Determine ICU vs non-ICU
  SELECT
    fsa.*,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_group
  FROM female_stroke_admissions fsa
  LEFT JOIN (
    SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
    ON fsa.hadm_id = icu.hadm_id
),
los_grouped AS (
  -- Calculate LOS and group
  SELECT
    *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) <= 5 THEN '≤5'
      ELSE '>5'
    END AS los_group
  FROM icu_status
),
comorbidity_burden AS (
  -- Count distinct diagnosis codes per admission
  SELECT
    lsg.subject_id,
    lsg.hadm_id,
    lsg.icu_group,
    lsg.los_group,
    lsg.los_days,
    lsg.hospital_expire_flag,
    COUNT(DISTINCT d.icd_code) AS n_comorbidities
  FROM los_grouped lsg
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON lsg.subject_id = d.subject_id AND lsg.hadm_id = d.hadm_id
  GROUP BY
    lsg.subject_id, lsg.hadm_id, lsg.icu_group, lsg.los_group, lsg.los_days, lsg.hospital_expire_flag
),
comorbidity_grouped AS (
  -- Bin comorbidity burden
  SELECT
    *,
    CASE
      WHEN n_comorbidities <= 2 THEN '0–2'
      WHEN n_comorbidities BETWEEN 3 AND 5 THEN '3–5'
      ELSE '>5'
    END AS comorbidity_group
  FROM comorbidity_burden
)
SELECT
  icu_group,
  los_group,
  comorbidity_group,
  COUNT(*) AS n_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
  SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS mortality_percent,
  -- Wilson score interval for 95% CI
  -- p̂ = deaths/n, n = total, z = 1.96
  -- Lower and upper bounds
  (
    (
      SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*))
      + POW(1.96,2)/(2*COUNT(*))
      - 1.96 * SQRT(
        SAFE_DIVIDE(
          SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*))
          * (1 - SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)))
          + POW(1.96,2)/(4*COUNT(*)),
          COUNT(*)
        )
      )
    )
    / (1 + POW(1.96,2)/COUNT(*))
  ) * 100 AS mortality_ci_lower_percent,
  (
    (
      SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*))
      + POW(1.96,2)/(2*COUNT(*))
      + 1.96 * SQRT(
        SAFE_DIVIDE(
          SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*))
          * (1 - SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)))
          + POW(1.96,2)/(4*COUNT(*)),
          COUNT(*)
        )
      )
    )
    / (1 + POW(1.96,2)/COUNT(*))
  ) * 100 AS mortality_ci_upper_percent
FROM comorbidity_grouped
GROUP BY icu_group, los_group, comorbidity_group
ORDER BY icu_group, los_group, comorbidity_group;