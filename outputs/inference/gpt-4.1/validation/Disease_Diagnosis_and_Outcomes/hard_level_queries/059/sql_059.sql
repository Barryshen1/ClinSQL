WITH
-- 1. Get male patients aged 59-69
male_59_69 AS (
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 59 AND 69
),

-- 2. Get admissions for these patients
adm_59_69 AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN male_59_69 p ON a.subject_id = p.subject_id
),

-- 3. Identify DKA admissions (ICD-9: 250.1*, ICD-10: E10.1*, E11.1*, E13.1*, E14.1*)
dka_icd AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND LEFT(icd_code,5) = '250.1')
    OR (icd_version = 10 AND (
      LEFT(icd_code,6) IN ('E101','E111','E131','E141')
    ))
),

-- 4. Identify AKI admissions (ICD-9: 584*, ICD-10: N17*)
aki_icd AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND LEFT(icd_code,3) = '584')
    OR (icd_version = 10 AND LEFT(icd_code,3) = 'N17')
),

-- 5. Identify ARDS admissions (ICD-9: 518.82, ICD-10: J80)
ards_icd AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND icd_code = '51882')
    OR (icd_version = 10 AND icd_code = 'J80')
),

-- 6. CCI map: one row per comorbidity prefix
cci_map AS (
  SELECT 'MI' AS comorb, '410' AS prefix, 1 AS weight UNION ALL
  SELECT 'MI', '412', 1 UNION ALL
  SELECT 'MI', 'I21', 1 UNION ALL
  SELECT 'MI', 'I22', 1 UNION ALL
  SELECT 'MI', 'I252', 1 UNION ALL
  SELECT 'CHF', '428', 1 UNION ALL
  SELECT 'CHF', 'I50', 1 UNION ALL
  SELECT 'PVD', '4439', 1 UNION ALL
  SELECT 'PVD', 'I73', 1 UNION ALL
  SELECT 'PVD', 'I70', 1 UNION ALL
  SELECT 'PVD', 'I71', 1 UNION ALL
  SELECT 'PVD', 'I72', 1 UNION ALL
  SELECT 'PVD', 'I77', 1 UNION ALL
  SELECT 'CVD', '430', 1 UNION ALL
  SELECT 'CVD', '431', 1 UNION ALL
  SELECT 'CVD', '432', 1 UNION ALL
  SELECT 'CVD', '433', 1 UNION ALL
  SELECT 'CVD', '434', 1 UNION ALL
  SELECT 'CVD', '435', 1 UNION ALL
  SELECT 'CVD', '436', 1 UNION ALL
  SELECT 'CVD', '437', 1 UNION ALL
  SELECT 'CVD', '438', 1 UNION ALL
  SELECT 'CVD', 'I60', 1 UNION ALL
  SELECT 'CVD', 'I61', 1 UNION ALL
  SELECT 'CVD', 'I62', 1 UNION ALL
  SELECT 'CVD', 'I63', 1 UNION ALL
  SELECT 'CVD', 'I64', 1 UNION ALL
  SELECT 'CVD', 'G45', 1 UNION ALL
  SELECT 'CVD', 'G46', 1 UNION ALL
  SELECT 'Dementia', '290', 1 UNION ALL
  SELECT 'Dementia', 'F00', 1 UNION ALL
  SELECT 'Dementia', 'F01', 1 UNION ALL
  SELECT 'Dementia', 'F02', 1 UNION ALL
  SELECT 'Dementia', 'F03', 1 UNION ALL
  SELECT 'Dementia', 'G30', 1 UNION ALL
  SELECT 'COPD', '490', 1 UNION ALL
  SELECT 'COPD', '491', 1 UNION ALL
  SELECT 'COPD', '492', 1 UNION ALL
  SELECT 'COPD', '493', 1 UNION ALL
  SELECT 'COPD', '494', 1 UNION ALL
  SELECT 'COPD', '495', 1 UNION ALL
  SELECT 'COPD', '496', 1 UNION ALL
  SELECT 'COPD', 'J40', 1 UNION ALL
  SELECT 'COPD', 'J41', 1 UNION ALL
  SELECT 'COPD', 'J42', 1 UNION ALL
  SELECT 'COPD', 'J43', 1 UNION ALL
  SELECT 'COPD', 'J44', 1 UNION ALL
  SELECT 'COPD', 'J45', 1 UNION ALL
  SELECT 'COPD', 'J46', 1 UNION ALL
  SELECT 'COPD', 'J47', 1 UNION ALL
  SELECT 'Diabetes', '250', 1 UNION ALL
  SELECT 'Diabetes', 'E10', 1 UNION ALL
  SELECT 'Diabetes', 'E11', 1 UNION ALL
  SELECT 'Diabetes', 'E13', 1 UNION ALL
  SELECT 'Diabetes', 'E14', 1 UNION ALL
  SELECT 'Cancer', '140', 2 UNION ALL
  SELECT 'Cancer', '141', 2 UNION ALL
  SELECT 'Cancer', '142', 2 UNION ALL
  SELECT 'Cancer', '143', 2 UNION ALL
  SELECT 'Cancer', '144', 2 UNION ALL
  SELECT 'Cancer', '145', 2 UNION ALL
  SELECT 'Cancer', '146', 2 UNION ALL
  SELECT 'Cancer', '147', 2 UNION ALL
  SELECT 'Cancer', '148', 2 UNION ALL
  SELECT 'Cancer', '149', 2 UNION ALL
  SELECT 'Cancer', '150', 2 UNION ALL
  SELECT 'Cancer', '151', 2 UNION ALL
  SELECT 'Cancer', '152', 2 UNION ALL
  SELECT 'Cancer', '153', 2 UNION ALL
  SELECT 'Cancer', '154', 2 UNION ALL
  SELECT 'Cancer', '155', 2 UNION ALL
  SELECT 'Cancer', '156', 2 UNION ALL
  SELECT 'Cancer', '157', 2 UNION ALL
  SELECT 'Cancer', '158', 2 UNION ALL
  SELECT 'Cancer', '159', 2 UNION ALL
  SELECT 'Cancer', 'C00', 2 UNION ALL
  SELECT 'Cancer', 'C01', 2 UNION ALL
  SELECT 'Cancer', 'C02', 2 UNION ALL
  SELECT 'Cancer', 'C03', 2 UNION ALL
  SELECT 'Cancer', 'C04', 2 UNION ALL
  SELECT 'Cancer', 'C05', 2 UNION ALL
  SELECT 'Cancer', 'C06', 2 UNION ALL
  SELECT 'Cancer', 'C07', 2 UNION ALL
  SELECT 'Cancer', 'C08', 2 UNION ALL
  SELECT 'Cancer', 'C09', 2 UNION ALL
  SELECT 'Cancer', 'C10', 2 UNION ALL
  SELECT 'Cancer', 'C11', 2 UNION ALL
  SELECT 'Cancer', 'C12', 2 UNION ALL
  SELECT 'Cancer', 'C13', 2 UNION ALL
  SELECT 'Cancer', 'C14', 2 UNION ALL
  SELECT 'Cancer', 'C15', 2 UNION ALL
  SELECT 'Cancer', 'C16', 2 UNION ALL
  SELECT 'Cancer', 'C17', 2 UNION ALL
  SELECT 'Cancer', 'C18', 2 UNION ALL
  SELECT 'Cancer', 'C19', 2 UNION ALL
  SELECT 'Cancer', 'C20', 2 UNION ALL
  SELECT 'Cancer', 'C21', 2 UNION ALL
  SELECT 'Cancer', 'C22', 2 UNION ALL
  SELECT 'Cancer', 'C23', 2 UNION ALL
  SELECT 'Cancer', 'C24', 2 UNION ALL
  SELECT 'Cancer', 'C25', 2 UNION ALL
  SELECT 'Cancer', 'C26', 2
),

-- 7. For each admission, get comorbidities present
admission_comorbs AS (
  SELECT
    d.hadm_id,
    m.comorb,
    MAX(m.weight) AS weight
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN cci_map m
    ON LEFT(d.icd_code, LENGTH(m.prefix)) = m.prefix
  GROUP BY d.hadm_id, m.comorb
),

-- 8. Sum weights per admission for CCI
cci_per_adm AS (
  SELECT
    hadm_id,
    SUM(weight) AS cci
  FROM admission_comorbs
  GROUP BY hadm_id
),

-- 9. DKA cohort admissions with CCI
dka_adms AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    cci.cci
  FROM adm_59_69 adm
  JOIN dka_icd dka ON adm.hadm_id = dka.hadm_id
  LEFT JOIN cci_per_adm cci ON adm.hadm_id = cci.hadm_id
),

-- 10. General inpatient cohort (male, 59-69, not DKA)
gen_adms AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    cci.cci
  FROM adm_59_69 adm
  LEFT JOIN dka_icd dka ON adm.hadm_id = dka.hadm_id
  LEFT JOIN cci_per_adm cci ON adm.hadm_id = cci.hadm_id
  WHERE dka.hadm_id IS NULL
),

-- 11. Add AKI/ARDS flags
dka_adms_flags AS (
  SELECT
    dka.*,
    CASE WHEN aki.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki,
    CASE WHEN ards.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ards
  FROM dka_adms dka
  LEFT JOIN aki_icd aki ON dka.hadm_id = aki.hadm_id
  LEFT JOIN ards_icd ards ON dka.hadm_id = ards.hadm_id
),

gen_adms_flags AS (
  SELECT
    gen.*,
    CASE WHEN aki.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki,
    CASE WHEN ards.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ards
  FROM gen_adms gen
  LEFT JOIN aki_icd aki ON gen.hadm_id = aki.hadm_id
  LEFT JOIN ards_icd ards ON gen.hadm_id = ards.hadm_id
),

-- 12. Calculate 30-day mortality
dka_final AS (
  SELECT
    *,
    CASE
      WHEN deathtime IS NOT NULL AND DATETIME_DIFF(deathtime, admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_30d,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM dka_adms_flags
),

gen_final AS (
  SELECT
    *,
    CASE
      WHEN deathtime IS NOT NULL AND DATETIME_DIFF(deathtime, admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_30d,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM gen_adms_flags
),

-- 13. For percentile: collect general cohort CCI values
gen_cci_dist AS (
  SELECT cci
  FROM gen_final
  WHERE cci IS NOT NULL
),

-- 14. Calculate percentile for each DKA admission
dka_with_percentile AS (
  SELECT
    dka.*,
    (
      SELECT
        100.0 * COUNTIF(g.cci < dka.cci) / COUNT(*)
      FROM gen_cci_dist g
      WHERE g.cci IS NOT NULL
    ) AS cci_percentile
  FROM dka_final dka
)

-- 15. Aggregate results
SELECT
  'DKA cohort' AS cohort,
  COUNT(*) AS n_admissions,
  ROUND(AVG(cci),2) AS mean_cci,
  ROUND(AVG(died_30d),3) AS mortality_30d_rate,
  ROUND(AVG(has_aki),3) AS aki_rate,
  ROUND(AVG(has_ards),3) AS ards_rate,
  ROUND(AVG(CASE WHEN hospital_expire_flag = 0 THEN los ELSE NULL END),2) AS survivor_los,
  ROUND(AVG(cci_percentile),1) AS mean_cci_percentile
FROM dka_with_percentile

UNION ALL

SELECT
  'General cohort' AS cohort,
  COUNT(*) AS n_admissions,
  ROUND(AVG(cci),2) AS mean_cci,
  ROUND(AVG(died_30d),3) AS mortality_30d_rate,
  ROUND(AVG(has_aki),3) AS aki_rate,
  ROUND(AVG(has_ards),3) AS ards_rate,
  ROUND(AVG(CASE WHEN hospital_expire_flag = 0 THEN los ELSE NULL END),2) AS survivor_los,
  NULL AS mean_cci_percentile
FROM gen_final;