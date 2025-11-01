WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN 'LOS 1-3'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN 'LOS 4-7'
    END AS los_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.hadm_id IN (
      SELECT d.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE LOWER(dd.long_title) LIKE '%septic shock%'
    )
),
icu_flag AS (
  SELECT DISTINCT
    hadm_id,
    1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
ultrasound_counts AS (
  SELECT
    pr.hadm_id,
    COUNT(*) AS us_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%ultrasound%'
     OR LOWER(dp.long_title) LIKE '%echo%'
  GROUP BY pr.hadm_id
)
SELECT
  los_category,
  icu_flag,
  APPROX_QUANTILES(us_count, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(us_count, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(us_count, 100)[OFFSET(75)] AS p75
FROM (
  SELECT
    c.hadm_id,
    c.los_category,
    IFNULL(i.icu_flag, 0) AS icu_flag,
    IFNULL(u.us_count, 0) AS us_count
  FROM cohort c
  LEFT JOIN icu_flag i
    ON c.hadm_id = i.hadm_id
  LEFT JOIN ultrasound_counts u
    ON c.hadm_id = u.hadm_id
  WHERE c.los_category IS NOT NULL
)
GROUP BY los_category, icu_flag
ORDER BY los_category, icu_flag;