WITH cohort AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN '<=5'
      ELSE '>5'
    END AS los_bin,
    CASE
      WHEN EXISTS(
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.subject_id = a.subject_id
          AND i.hadm_id = a.hadm_id
          AND i.intime <= TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
      ) THEN 'Yes'
      ELSE 'No'
    END AS icu_day1
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.dischtime IS NOT NULL
    AND EXISTS(
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id = a.hadm_id
        AND di.icd_version = 10
        AND di.icd_code LIKE 'I21%'
    )
    AND NOT EXISTS(
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` de
      WHERE de.hadm_id = a.hadm_id
        AND de.icd_version = 10
        AND (de.icd_code LIKE 'J96%' OR de.icd_code LIKE 'R57%')
    )
)
SELECT
  los_bin,
  icu_day1,
  COUNT(*) AS n,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_pct,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
FROM
  cohort
GROUP BY
  los_bin,
  icu_day1
ORDER BY
  los_bin,
  icu_day1;