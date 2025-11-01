WITH female_adms AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
),
gi_dx AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%gi bleed%' AND LOWER(dd.long_title) LIKE '%upper%' THEN 1 ELSE 0 END) AS has_upper,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%gi bleed%' AND LOWER(dd.long_title) LIKE '%lower%' THEN 1 ELSE 0 END) AS has_lower
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      USING (icd_code, icd_version)
  GROUP BY
    di.subject_id,
    di.hadm_id
),
cohort AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.hospital_expire_flag,
    f.los,
    CASE
      WHEN g.has_upper = 1 AND g.has_lower = 0 THEN 'upper'
      WHEN g.has_lower = 1 AND g.has_upper = 0 THEN 'lower'
      ELSE NULL
    END AS bleed_type
  FROM
    female_adms AS f
    JOIN gi_dx AS g
      ON f.subject_id = g.subject_id
     AND f.hadm_id    = g.hadm_id
  WHERE
    (g.has_upper + g.has_lower) = 1
),
los_bucket AS (
  SELECT
    *,
    CASE
      WHEN los BETWEEN 1 AND 2 THEN '1-2'
      WHEN los BETWEEN 3 AND 5 THEN '3-5'
      WHEN los BETWEEN 6 AND 9 THEN '6-9'
      ELSE '10+'
    END AS los_group
  FROM
    cohort
),
icu_flags AS (
  SELECT
    lb.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      WHERE icu.hadm_id = lb.hadm_id
        AND icu.intime < TIMESTAMP_ADD(lb.admittime, INTERVAL 1 DAY)
    ) AS day1_icu,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      WHERE icu.hadm_id = lb.hadm_id
    ) AS any_icu
  FROM
    los_bucket AS lb
)
SELECT
  bleed_type,
  los_group,
  CASE WHEN day1_icu THEN 'Y' ELSE 'N' END AS day1_icu,
  COUNT(*) AS n_admissions,
  SUM(hospital_expire_flag) AS n_deaths,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_pct,
  ROUND(100.0 * SUM(CASE WHEN any_icu THEN 1 ELSE 0 END) / COUNT(*), 1) AS icu_admission_rate
FROM
  icu_flags
GROUP BY
  bleed_type,
  los_group,
  day1_icu
ORDER BY
  bleed_type,
  los_group,
  day1_icu;