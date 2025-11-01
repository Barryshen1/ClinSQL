WITH admissions_with_age_gender AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),

admission_comorbidities AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%chronic kidney disease%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  GROUP BY
    hadm_id
),

admission_summary AS (
  SELECT
    a.hadm_id,
    a.los_days,
    a.hospital_expire_flag,
    COALESCE(c.has_ckd, 0) AS has_ckd,
    COALESCE(c.has_diabetes, 0) AS has_diabetes
  FROM
    admissions_with_age_gender a
  LEFT JOIN
    admission_comorbidities c
  ON
    a.hadm_id = c.hadm_id
),

stratified_stats AS (
  SELECT
    CASE
      WHEN los_days < 8 THEN 'LOS < 8 days'
      ELSE 'LOS >= 8 days'
    END AS los_group,
    COUNT(*) AS total_admissions,
    SUM(hospital_expire_flag) AS deaths,
    SUM(has_ckd) AS ckd_cases,
    SUM(has_diabetes) AS diabetes_cases
  FROM
    admission_summary
  GROUP BY
    los_group
)

SELECT
  los_group,
  ROUND(100.0 * deaths / total_admissions, 2) AS in_hospital_mortality_pct,
  ROUND(100.0 * ckd_cases / total_admissions, 2) AS ckd_prevalence_pct,
  ROUND(100.0 * diabetes_cases / total_admissions, 2) AS diabetes_prevalence_pct
FROM
  stratified_stats
ORDER BY
  los_group;