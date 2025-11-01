WITH age_filtered AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    (CAST(p.anchor_age AS INT64) + (EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64))) AS age_at_admit,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (CAST(p.anchor_age AS INT64) + (EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64))) BETWEEN 49 AND 59
),

sepsis_adms AS (
  SELECT DISTINCT af.subject_id, af.hadm_id
  FROM age_filtered af
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = af.subject_id
   AND di.hadm_id = af.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON ddi.icd_code = di.icd_code
   AND ddi.icd_version = di.icd_version
  WHERE (
          LOWER(ddi.long_title) LIKE '%sepsis%'
          OR LOWER(ddi.long_title) LIKE '%septicemia%'
        )
    -- exclude septic shock diagnoses for the same admission
    AND NOT EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
          JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi2
            ON ddi2.icd_code = di2.icd_code
           AND ddi2.icd_version = di2.icd_version
          WHERE di2.subject_id = af.subject_id
            AND di2.hadm_id = af.hadm_id
            AND LOWER(ddi2.long_title) LIKE '%septic shock%'
        )
),

ckd_flags AS (
  SELECT
    di.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%chronic kidney disease%' OR LOWER(dd.long_title) LIKE '%ckd%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = di.icd_code
   AND dd.icd_version = di.icd_version
  GROUP BY di.hadm_id
),

base AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    af.admittime,
    af.dischtime,
    af.deathtime,
    af.hospital_expire_flag
  FROM sepsis_adms s
  JOIN age_filtered af
    ON af.subject_id = s.subject_id
   AND af.hadm_id = s.hadm_id
)

SELECT
  CASE WHEN TIMESTAMP_DIFF(b.dischtime, b.admittime, DAY) <= 5 THEN '<=5' ELSE '>5' END AS los_group,
  IF(icu.hadm_id IS NOT NULL, 1, 0) AS day1_icu,
  COUNT(*) AS N,
  ROUND(100.0 * SUM(CASE WHEN (b.deathtime IS NOT NULL OR b.hospital_expire_flag = 1) THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_pct,
  ROUND(100.0 * SUM(COALESCE(ck.has_ckd, 0)) / COUNT(*), 2) AS ckd_prev,
  ROUND(100.0 * SUM(COALESCE(dia.has_diabetes, 0)) / COUNT(*), 2) AS diabetes_prev
FROM base b
LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON icu.subject_id = b.subject_id
 AND icu.hadm_id = b.hadm_id
 AND DATE(icu.intime) = DATE(b.admittime)
LEFT JOIN ckd_flags ck
  ON ck.hadm_id = b.hadm_id
LEFT JOIN ckd_flags dia
  ON dia.hadm_id = b.hadm_id
GROUP BY los_group, day1_icu
ORDER BY los_group, day1_icu;