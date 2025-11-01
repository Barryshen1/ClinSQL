WITH hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Flag for day‐1 ICU
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.hadm_id = a.hadm_id
          AND i.intime <= a.admittime + INTERVAL 1 DAY
      ) THEN 'ICU'
      ELSE 'Non-ICU'
    END AS day1_icu_flag,
    -- LOS category
    CASE
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_group,
    -- CKD flag
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND (
            (d.icd_version = 9 AND d.icd_code LIKE '585%')
            OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%')
          )
      ) THEN 1 ELSE 0
    END AS ckd_flag,
    -- Diabetes flag
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND (
            (d.icd_version = 9 AND d.icd_code LIKE '250%')
            OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%'))
          )
      ) THEN 1 ELSE 0
    END AS dm_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    -- Must have a heart failure diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
stats AS (
  SELECT
    day1_icu_flag,
    los_group,
    COUNT(*) AS n_patients,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_pct,
    -- median LOS via approximate quantiles
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
    ROUND(100.0 * SUM(ckd_flag) / COUNT(*), 1) AS ckd_prevalence_pct,
    ROUND(100.0 * SUM(dm_flag) / COUNT(*), 1) AS diabetes_prevalence_pct
  FROM hf_admissions
  GROUP BY day1_icu_flag, los_group
  ORDER BY day1_icu_flag, los_group
)
SELECT * FROM stats;