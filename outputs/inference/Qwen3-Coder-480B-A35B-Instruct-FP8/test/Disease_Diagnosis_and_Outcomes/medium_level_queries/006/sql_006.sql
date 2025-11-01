WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),

sepsis_admissions AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.los_days,
    c.hospital_expire_flag
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    c.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    REGEXP_CONTAINS(d.long_title, r"(?i)sepsis") 
    AND NOT REGEXP_CONTAINS(d.long_title, r"(?i)shock")
),

los_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM
    sepsis_admissions
),

comorbidities AS (
  SELECT
    lq.hadm_id,
    lq.los_quartile,
    lq.hospital_expire_flag,
    MAX(CASE WHEN d.long_title LIKE "%diabetes%" THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN d.long_title LIKE "%kidney%" OR d.long_title LIKE "%CKD%" THEN 1 ELSE 0 END) AS has_ckd
  FROM
    los_quartiles lq
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    lq.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  GROUP BY
    lq.hadm_id, lq.los_quartile, lq.hospital_expire_flag
)

SELECT
  los_quartile,
  COUNT(*) AS admission_count,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(has_ckd) AS ckd_prevalence,
  AVG(has_diabetes) AS diabetes_prevalence
FROM
  comorbidities
GROUP BY
  los_quartile
ORDER BY
  los_quartile;