WITH base_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    p.dod,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 67 AND 77
),

acs_codes AS (
  SELECT '410%' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '411.0', 9 UNION ALL
  SELECT '411.1', 9 UNION ALL
  SELECT '411.8', 9 UNION ALL
  SELECT '413%', 9 UNION ALL
  SELECT 'I20.0', 10 UNION ALL
  SELECT 'I21%', 10 UNION ALL
  SELECT 'I22%', 10 UNION ALL
  SELECT 'I24.0', 10 UNION ALL
  SELECT 'I24.8', 10 UNION ALL
  SELECT 'I24.9', 10
),

acs_admissions AS (
  SELECT DISTINCT adm.hadm_id
  FROM base_admissions adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN acs_codes acs
    ON diag.icd_code LIKE acs.icd_code
    AND diag.icd_version = acs.icd_version
),

icu_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

cohort AS (
  SELECT 
    adm.*,
    1 AS in_cohort
  FROM base_admissions adm
  WHERE adm.hadm_id IN (SELECT hadm_id FROM acs_admissions)
    AND adm.hadm_id IN (SELECT hadm_id FROM icu_admissions)
),

control AS (
  SELECT 
    adm.*,
    0 AS in_cohort
  FROM base_admissions adm
  WHERE adm.hadm_id NOT IN (SELECT hadm_id FROM acs_admissions)
),

cardiac_comp_codes AS (
  SELECT '427.5' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '428%', 9 UNION ALL
  SELECT '426%', 9 UNION ALL
  SELECT '427.0', 9 UNION ALL
  SELECT '427.1', 9 UNION ALL
  SELECT '427.2', 9 UNION ALL
  SELECT '427.3', 9 UNION ALL
  SELECT '427.4', 9 UNION ALL
  SELECT '427.6', 9 UNION ALL
  SELECT '427.8', 9 UNION ALL
  SELECT '427.9', 9 UNION ALL
  SELECT 'I46%', 10 UNION ALL
  SELECT 'I50%', 10 UNION ALL
  SELECT 'I44%', 10 UNION ALL
  SELECT 'I45%', 10 UNION ALL
  SELECT 'I47%', 10 UNION ALL
  SELECT 'I48%', 10 UNION ALL
  SELECT 'I49%', 10
),

neuro_comp_codes AS (
  SELECT '430' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '431', 9 UNION ALL
  SELECT '433%', 9 UNION ALL
  SELECT '434%', 9 UNION ALL
  SELECT '436', 9 UNION ALL
  SELECT '435.9', 9 UNION ALL
  SELECT 'I60%', 10 UNION ALL
  SELECT 'I61%', 10 UNION ALL
  SELECT 'I62%', 10 UNION ALL
  SELECT 'I63%', 10 UNION ALL
  SELECT 'I64%', 10 UNION ALL
  SELECT 'I67.89', 10 UNION ALL
  SELECT 'G45.9', 10
),

combined_with_complications AS (
  SELECT 
    c.*,
    CASE WHEN c.dod IS NOT NULL AND c.dod <= DATETIME_ADD(c.admittime, INTERVAL 30 DAY) THEN 1 ELSE 0 END AS mortality_30d,
    CASE WHEN EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
          WHERE diag.hadm_id = c.hadm_id
            AND EXISTS (
              SELECT 1 
              FROM cardiac_comp_codes cc 
              WHERE diag.icd_code LIKE cc.icd_code
                AND diag.icd_version = cc.icd_version
            )
        ) THEN 1 ELSE 0 END AS cardiac_comp,
    CASE WHEN EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
          WHERE diag.hadm_id = c.hadm_id
            AND EXISTS (
              SELECT 1 
              FROM neuro_comp_codes nc 
              WHERE diag.icd_code LIKE nc.icd_code
                AND diag.icd_version = nc.icd_version
            )
        ) THEN 1 ELSE 0 END AS neuro_comp,
    CASE WHEN c.hospital_expire_flag = 0 THEN DATETIME_DIFF(c.dischtime, c.admittime, DAY) END AS los_days
  FROM (
    SELECT * FROM cohort
    UNION ALL
    SELECT * FROM control
  ) c
),

group_aggregates AS (
  SELECT 
    in_cohort,
    COUNT(*) AS total_admissions,
    AVG(mortality_30d) AS mortality_30d_rate,
    AVG(cardiac_comp) AS cardiac_comp_rate,
    AVG(neuro_comp) AS neuro_comp_rate,
    AVG(los_days) AS mean_los_survivors
  FROM combined_with_complications
  GROUP BY in_cohort
),

control_survivors_los AS (
  SELECT los_days
  FROM combined_with_complications
  WHERE in_cohort = 0 
    AND los_days IS NOT NULL
),

cohort_survivors AS (
  SELECT 
    hadm_id,
    los_days
  FROM combined_with_complications
  WHERE in_cohort = 1 
    AND los_days IS NOT NULL
),

cohort_percentiles AS (
  SELECT 
    c.hadm_id,
    c.los_days,
    (SELECT COUNT(*) 
     FROM control_survivors_los cl 
     WHERE cl.los_days <= c.los_days) * 100.0 / (SELECT COUNT(*) FROM control_survivors_los) AS percentile
  FROM cohort_survivors c
),

avg_percentile AS (
  SELECT AVG(percentile) AS avg_percentile
  FROM cohort_percentiles
)

SELECT 
  'Cohort (ACS + ICU)' AS group_label,
  total_admissions,
  mortality_30d_rate,
  cardiac_comp_rate,
  neuro_comp_rate,
  mean_los_survivors,
  (SELECT avg_percentile FROM avg_percentile) AS avg_los_percentile_in_control
FROM group_aggregates
WHERE in_cohort = 1

UNION ALL

SELECT 
  'Control (General Inpatients)' AS group_label,
  total_admissions,
  mortality_30d_rate,
  cardiac_comp_rate,
  neuro_comp_rate,
  mean_los_survivors,
  NULL AS avg_los_percentile_in_control
FROM group_aggregates
WHERE in_cohort = 0;