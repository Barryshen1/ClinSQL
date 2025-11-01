WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
),

heart_failure_admits AS (
  SELECT DISTINCT
    c.*
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%heart failure%'
),

comorbidity_counts AS (
  SELECT
    hf.hadm_id,
    COUNT(DISTINCT CASE
      WHEN LOWER(dd.long_title) NOT LIKE '%heart failure%' THEN d.icd_code
    END) AS comorbidity_count
  FROM
    heart_failure_admits hf
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON hf.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  GROUP BY
    hf.hadm_id
),

stratified_data AS (
  SELECT
    hf.*,
    cc.comorbidity_count,
    CASE
      WHEN cc.comorbidity_count BETWEEN 0 AND 1 THEN '0-1'
      WHEN cc.comorbidity_count = 2 THEN '2'
      ELSE '3+'
    END AS comorbidity_group,
    CASE WHEN hf.los_days < 8 THEN '<8' ELSE '>=8' END AS los_group,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%chronic kidney disease%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    heart_failure_admits hf
  JOIN
    comorbidity_counts cc
    ON hf.hadm_id = cc.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON hf.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  GROUP BY
    hf.subject_id, hf.hadm_id, hf.admittime, hf.dischtime, hf.hospital_expire_flag,
    hf.los_days, hf.icu_status, cc.comorbidity_count, comorbidity_group, los_group
)

SELECT
  icu_status,
  los_group,
  comorbidity_group,
  COUNT(*) AS n_patients,
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
  AVG(has_ckd) * 100 AS ckd_prevalence_percent,
  AVG(has_diabetes) * 100 AS diabetes_prevalence_percent
FROM
  stratified_data
GROUP BY
  icu_status, los_group, comorbidity_group
ORDER BY
  icu_status, los_group, comorbidity_group;