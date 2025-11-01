WITH female_stroke_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    diag.icd_code,
    diag.icd_version,
    diag_icd.long_title AS diagnosis,
    CASE
      WHEN (
        -- Ischemic stroke ICD-10
        (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^I63'))
        -- Ischemic stroke ICD-9
        OR (diag.icd_version = 9 AND (REGEXP_CONTAINS(diag.icd_code, r'^434') OR REGEXP_CONTAINS(diag.icd_code, r'^433')))
      ) THEN 'Ischemic'
      WHEN (
        -- Hemorrhagic stroke ICD-10
        (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^I61'))
        -- Hemorrhagic stroke ICD-9
        OR (diag.icd_version = 9 AND (diag.icd_code = '431' OR REGEXP_CONTAINS(diag.icd_code, r'^432')))
      ) THEN 'Hemorrhagic'
      ELSE NULL
    END AS stroke_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag_icd
      ON diag.icd_code = diag_icd.icd_code AND diag.icd_version = diag_icd.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 52 AND 62
),
stroke_admissions AS (
  -- Only admissions with stroke diagnosis
  SELECT DISTINCT
    subject_id,
    hadm_id,
    anchor_age,
    admittime,
    dischtime,
    hospital_expire_flag,
    stroke_type
  FROM female_stroke_admissions
  WHERE stroke_type IS NOT NULL
),
comorbidities AS (
  -- For each admission, get all comorbidities (excluding stroke, CKD, diabetes)
  SELECT
    diag.hadm_id,
    diag.icd_code,
    diag.icd_version,
    diag_icd.long_title,
    CASE
      WHEN (
        -- CKD ICD-10
        (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^N18'))
        -- CKD ICD-9
        OR (diag.icd_version = 9 AND REGEXP_CONTAINS(diag.icd_code, r'^585'))
      ) THEN 1 ELSE 0 END AS is_ckd,
    CASE
      WHEN (
        -- Diabetes ICD-10
        (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^E1[0-4]'))
        -- Diabetes ICD-9
        OR (diag.icd_version = 9 AND REGEXP_CONTAINS(diag.icd_code, r'^250'))
      ) THEN 1 ELSE 0 END AS is_diabetes,
    CASE
      WHEN (
        -- Ischemic stroke ICD-10
        (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^I63'))
        -- Ischemic stroke ICD-9
        OR (diag.icd_version = 9 AND (REGEXP_CONTAINS(diag.icd_code, r'^434') OR REGEXP_CONTAINS(diag.icd_code, r'^433')))
        -- Hemorrhagic stroke ICD-10
        OR (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^I61'))
        -- Hemorrhagic stroke ICD-9
        OR (diag.icd_version = 9 AND (diag.icd_code = '431' OR REGEXP_CONTAINS(diag.icd_code, r'^432')))
      ) THEN 1 ELSE 0 END AS is_stroke
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag_icd
      ON diag.icd_code = diag_icd.icd_code AND diag.icd_version = diag_icd.icd_version
),
admission_comorbidity_summary AS (
  -- For each admission, summarize CKD, diabetes, and comorbidity count
  SELECT
    sa.subject_id,
    sa.hadm_id,
    sa.anchor_age,
    sa.admittime,
    sa.dischtime,
    sa.hospital_expire_flag,
    sa.stroke_type,
    MAX(c.is_ckd) AS has_ckd,
    MAX(c.is_diabetes) AS has_diabetes,
    COUNTIF(c.is_stroke = 0 AND c.is_ckd = 0 AND c.is_diabetes = 0) AS comorbidity_count
  FROM stroke_admissions sa
    LEFT JOIN comorbidities c
      ON sa.hadm_id = c.hadm_id
  GROUP BY
    sa.subject_id, sa.hadm_id, sa.anchor_age, sa.admittime, sa.dischtime, sa.hospital_expire_flag, sa.stroke_type
),
admission_with_los AS (
  SELECT
    *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE WHEN DATETIME_DIFF(dischtime, admittime, DAY) < 8 THEN '<8' ELSE '≥8' END AS los_group
  FROM admission_comorbidity_summary
),
admission_with_tertile AS (
  -- Assign comorbidity tertile within each stroke type
  SELECT
    *,
    NTILE(3) OVER (PARTITION BY stroke_type ORDER BY comorbidity_count) AS comorbidity_tertile
  FROM admission_with_los
)
SELECT
  stroke_type,
  comorbidity_tertile,
  los_group,
  COUNT(*) AS n_admissions,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS in_hospital_mortality_pct,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  ROUND(100 * SUM(has_ckd) / COUNT(*), 1) AS ckd_prevalence_pct,
  ROUND(100 * SUM(has_diabetes) / COUNT(*), 1) AS diabetes_prevalence_pct
FROM admission_with_tertile
GROUP BY stroke_type, comorbidity_tertile, los_group
ORDER BY stroke_type, comorbidity_tertile, los_group;