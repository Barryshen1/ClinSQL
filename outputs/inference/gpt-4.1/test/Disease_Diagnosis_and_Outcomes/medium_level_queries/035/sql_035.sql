WITH
-- 1. Get all admissions for women aged 69–79
base_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.gender,
    pat.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 69 AND 79
),

-- 2. Identify GI bleed admissions (upper/lower)
gi_bleed_admissions AS (
  SELECT
    ba.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
          ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
        WHERE diag.hadm_id = ba.hadm_id
          AND (
            -- Upper GI bleed ICD codes
            diag.icd_code IN ('K92.0','K92.1','K25.0','K25.2','K26.0','K26.2','K27.0','K27.2','K28.0','K28.2','I85.01','I85.11')
            OR LOWER(dicd.long_title) LIKE '%upper gastrointestinal hemorrhage%'
            OR LOWER(dicd.long_title) LIKE '%esophageal varices with bleeding%'
            OR LOWER(dicd.long_title) LIKE '%gastric ulcer with hemorrhage%'
            OR LOWER(dicd.long_title) LIKE '%duodenal ulcer with hemorrhage%'
            OR LOWER(dicd.long_title) LIKE '%gastrointestinal hemorrhage%'
            OR LOWER(dicd.long_title) LIKE '%hematemesis%'
          )
      ) THEN 'Upper'
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
          ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
        WHERE diag.hadm_id = ba.hadm_id
          AND (
            -- Lower GI bleed ICD codes
            diag.icd_code IN ('K62.5','K92.2','K64.8','K55.1','K57.1','K57.3','K57.5','K57.9')
            OR LOWER(dicd.long_title) LIKE '%lower gastrointestinal hemorrhage%'
            OR LOWER(dicd.long_title) LIKE '%rectal bleeding%'
            OR LOWER(dicd.long_title) LIKE '%anal bleeding%'
            OR LOWER(dicd.long_title) LIKE '%melena%'
            OR LOWER(dicd.long_title) LIKE '%hematochezia%'
          )
      ) THEN 'Lower'
      ELSE NULL
    END AS gi_bleed_type
  FROM base_admissions ba
),

-- 3. Filter to admissions with GI bleed type
filtered_admissions AS (
  SELECT *
  FROM gi_bleed_admissions
  WHERE gi_bleed_type IS NOT NULL
),

-- 4. Calculate LOS and bin
admissions_with_los AS (
  SELECT
    *,
    SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) AS los_days,
    CASE
      WHEN SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) BETWEEN 1 AND 2 THEN '1-2'
      WHEN SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) BETWEEN 3 AND 5 THEN '3-5'
      WHEN SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) BETWEEN 6 AND 9 THEN '6-9'
      WHEN SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) >= 10 THEN '>=10'
      ELSE NULL
    END AS los_bin
  FROM filtered_admissions
),

-- 5. ICU admission and day-1 ICU status
icu_info AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.gi_bleed_type,
    adm.los_days,
    adm.los_bin,
    adm.hospital_expire_flag,
    -- ICU admission: at least one ICU stay
    CASE WHEN COUNT(icu.stay_id) > 0 THEN 1 ELSE 0 END AS icu_admit,
    -- Day-1 ICU: any ICU stay overlaps with first 24h of admission
    CASE WHEN
      SUM(
        CASE
          WHEN icu.intime < TIMESTAMP_ADD(adm.admittime, INTERVAL 1 DAY)
               AND icu.outtime > adm.admittime
          THEN 1 ELSE 0 END
      ) > 0
      THEN 1 ELSE 0
    END AS day1_icu
  FROM admissions_with_los adm
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE adm.los_bin IS NOT NULL
  GROUP BY
    adm.subject_id, adm.hadm_id, adm.gi_bleed_type, adm.los_days, adm.los_bin, adm.hospital_expire_flag
),

-- 6. Aggregate by GI bleed type, LOS bin, and day-1 ICU status
final_agg AS (
  SELECT
    gi_bleed_type,
    los_bin,
    day1_icu,
    COUNT(*) AS n_admissions,
    ROUND(100.0 * SUM(icu_admit) / COUNT(*), 1) AS icu_admission_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS in_hosp_mortality_pct
  FROM icu_info
  GROUP BY gi_bleed_type, los_bin, day1_icu
)

SELECT
  gi_bleed_type,
  los_bin,
  CASE day1_icu WHEN 1 THEN 'Day-1 ICU' ELSE 'No Day-1 ICU' END AS day1_icu_status,
  n_admissions,
  icu_admission_rate_pct,
  in_hosp_mortality_pct
FROM final_agg
ORDER BY gi_bleed_type, los_bin, day1_icu DESC;