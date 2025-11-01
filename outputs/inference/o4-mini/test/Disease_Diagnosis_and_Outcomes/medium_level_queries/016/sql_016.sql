WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    -- compute LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- restrict to males age 40–50
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    -- only admissions with at least one AMI diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code
        AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%acute myocardial infarction%'
    )
    -- exclude any admission with shock
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd2
        ON d2.icd_code = dicd2.icd_code
        AND d2.icd_version = dicd2.icd_version
      WHERE d2.hadm_id = a.hadm_id
        AND LOWER(dicd2.long_title) LIKE '%shock%'
    )
    -- exclude any admission with respiratory failure
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d3
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd3
        ON d3.icd_code = dicd3.icd_code
        AND d3.icd_version = dicd3.icd_version
      WHERE d3.hadm_id = a.hadm_id
        AND LOWER(dicd3.long_title) LIKE '%respiratory failure%'
    )
),

icu_flag AS (
  SELECT
    c.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE icu.hadm_id = c.hadm_id
          AND icu.intime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
      ) THEN 1
      ELSE 0
    END AS icu_day1
  FROM cohort c
),

final AS (
  SELECT
    icu_day1,
    CASE
      WHEN los_days <= 5 THEN '<=5'
      ELSE '>5'
    END AS los_group,
    COUNT(*) AS n_patients,
    100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_pct,
    -- approximate median LOS
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days
  FROM icu_flag
  GROUP BY icu_day1, los_group
)

SELECT
  icu_day1,
  los_group,
  n_patients,
  ROUND(mortality_pct, 1) AS in_hospital_mortality_pct,
  median_los_days
FROM final
ORDER BY icu_day1 DESC, los_group;