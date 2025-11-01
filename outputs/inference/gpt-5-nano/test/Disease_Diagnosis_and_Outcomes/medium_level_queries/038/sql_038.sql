WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS admit_days,
    MAX(IF(icu.hadm_id IS NOT NULL, 1, 0)) AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON a.subject_id = icu.subject_id AND a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age >= 80 AND p.anchor_age <= 90
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
    p.anchor_age, p.gender
)

SELECT
  icu_flag,
  los_cat,
  COUNT(*) AS n_admissions,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
  SUM(ckd_flag) AS ckd_count,
  ROUND(100.0 * SUM(ckd_flag) / COUNT(*), 2) AS ckd_prevalence,
  SUM(diabetes_flag) AS diabetes_count,
  ROUND(100.0 * SUM(diabetes_flag) / COUNT(*), 2) AS diabetes_prevalence
FROM (
  SELECT
    b.*,
    CASE
      WHEN b.admit_days < 8 THEN 'lt8'
      ELSE 'ge8'
    END AS los_cat,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dci
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
          ON dci.icd_code = dd2.icd_code AND dci.icd_version = dd2.icd_version
        WHERE dci.hadm_id = b.hadm_id
          AND LOWER(dd2.long_title) LIKE '%chronic kidney disease%'
      ) THEN 1 ELSE 0
    END AS ckd_flag,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dci
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd3
          ON dci.icd_code = dd3.icd_code AND dci.icd_version = dd3.icd_version
        WHERE dci.hadm_id = b.hadm_id
          AND (
            LOWER(dd3.long_title) LIKE '%diabetes mellitus%'
            OR LOWER(dd3.long_title) LIKE '%diabetes%'
          )
      ) THEN 1 ELSE 0
    END AS diabetes_flag
  FROM base b
) t
GROUP BY icu_flag, los_cat
ORDER BY icu_flag, los_cat;