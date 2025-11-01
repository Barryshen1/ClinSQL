WITH candidate AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS LOS_DAYS,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(p.gender) IN ('m', 'male')
    AND ((p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 64 AND 74)
),

flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.LOS_DAYS,
    c.hospital_expire_flag,
    -- Sepsis presence (any sepsis/septicemia)
    MAX(CASE
          WHEN LOWER(dd.long_title) LIKE '%sepsis%' OR LOWER(dd.long_title) LIKE '%septicemia%'
          THEN 1 ELSE 0 END) AS has_sepsis,
    -- Septic shock exclusion
    MAX(CASE
          WHEN LOWER(dd.long_title) LIKE '%septic shock%'
          THEN 1 ELSE 0 END) AS has_sep_shock,
    -- Diabetes presence
    MAX(CASE
          WHEN LOWER(dd_diabetes.long_title) LIKE '%diabetes%'
          THEN 1 ELSE 0 END) AS dm_present,
    -- CKD presence
    MAX(CASE
          WHEN LOWER(dd_ckd.long_title) LIKE '%chronic kidney disease%'
               OR LOWER(dd_ckd.long_title) LIKE '%ckd%'
               OR LOWER(dd_ckd.long_title) LIKE '%kidney disease%'
          THEN 1 ELSE 0 END) AS ckd_present
  FROM candidate AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON c.subject_id = di.subject_id AND c.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_diabetes
    ON di.icd_code = dd_diabetes.icd_code AND di.icd_version = dd_diabetes.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_ckd
    ON di.icd_code = dd_ckd.icd_code AND di.icd_version = dd_ckd.icd_version
  GROUP BY c.subject_id, c.hadm_id, c.LOS_DAYS, c.hospital_expire_flag
),

quart AS (
  SELECT
    subject_id,
    hadm_id,
    LOS_DAYS,
    hospital_expire_flag,
    has_sepsis,
    has_sep_shock,
    dm_present,
    ckd_present,
    NTILE(4) OVER (ORDER BY LOS_DAYS) AS los_quartile
  FROM flags
  WHERE has_sepsis = 1 AND has_sep_shock = 0
)

SELECT
  los_quartile AS quartile,
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate,
  SUM(dm_present) / COUNT(*) AS diabetes_prevalence,
  SUM(ckd_present) / COUNT(*) AS ckd_prevalence
FROM quart
GROUP BY quartile
ORDER BY quartile;