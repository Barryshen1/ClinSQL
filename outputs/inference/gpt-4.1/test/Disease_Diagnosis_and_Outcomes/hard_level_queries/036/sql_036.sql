WITH
-- 1. Get pneumonia ICD codes (ICD-9: 480-486, ICD-10: J12-J18)
pneumonia_icd AS (
  SELECT icd_code, icd_version
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses
  WHERE
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^48[0-6]$'))
    OR
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J1[2-8]'))
),

-- 2. Major complication ICD codes (sepsis, ARDS, acute renal failure, shock, cardiac arrest)
major_complication_icd AS (
  SELECT icd_code, icd_version
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses
  WHERE
    -- Sepsis: ICD-9 99591, 99592, 78552; ICD-10 A40, A41
    (icd_version = 9 AND icd_code IN ('99591', '99592', '78552'))
    OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^A4[01]'))
    -- ARDS: ICD-9 51882; ICD-10 J80
    OR (icd_version = 9 AND icd_code = '51882')
    OR (icd_version = 10 AND icd_code = 'J80')
    -- Acute renal failure: ICD-9 584[0-9]; ICD-10 N17
    OR (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^584'))
    OR (icd_version = 10 AND icd_code = 'N17')
    -- Shock: ICD-9 7855[0-9]; ICD-10 R57
    OR (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^7855'))
    OR (icd_version = 10 AND icd_code = 'R57')
    -- Cardiac arrest: ICD-9 4275; ICD-10 I46
    OR (icd_version = 9 AND icd_code = '4275')
    OR (icd_version = 10 AND icd_code = 'I46')
),

-- 3. Elixhauser comorbidity ICD codes (simplified: count unique comorbidities per hadm_id)
elixhauser_icd AS (
  SELECT DISTINCT icd_code, icd_version, 'comorbidity' AS flag
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses
  WHERE
    -- Use MIT-LCP mapping: see https://github.com/MIT-LCP/mimic-code/blob/main/concepts/comorbidity/elixhauser.sql
    -- Here, we use a simplified mapping: select all ICD codes mapped to Elixhauser
    long_title LIKE '%[Elixhauser]%'
),

-- 4. Admissions with pneumonia
pneumonia_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.deathtime, adm.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions adm
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
    ON adm.hadm_id = diag.hadm_id
  JOIN pneumonia_icd pn
    ON diag.icd_code = pn.icd_code AND diag.icd_version = pn.icd_version
),

-- 5. Add patient demographics
pneumonia_patients AS (
  SELECT pa.subject_id, pa.gender, pa.anchor_age, pa.dod, pn.hadm_id, pn.admittime, pn.dischtime, pn.deathtime, pn.hospital_expire_flag
  FROM pneumonia_admissions pn
  JOIN physionet-data.mimiciv_3_1_hosp.patients pa
    ON pn.subject_id = pa.subject_id
  WHERE pa.gender = 'M' AND pa.anchor_age BETWEEN 73 AND 83
),

-- 6. Calculate Elixhauser comorbidity count per admission
elixhauser_counts AS (
  SELECT
    diag.hadm_id,
    COUNT(DISTINCT diag.icd_code) AS elixhauser_count
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
  JOIN elixhauser_icd elx
    ON diag.icd_code = elx.icd_code AND diag.icd_version = elx.icd_version
  GROUP BY diag.hadm_id
),

-- 7. Add comorbidity to cohort
cohort AS (
  SELECT
    pp.*,
    COALESCE(ec.elixhauser_count, 0) AS elixhauser_count
  FROM pneumonia_patients pp
  LEFT JOIN elixhauser_counts ec
    ON pp.hadm_id = ec.hadm_id
),

-- 8. Get top quartile threshold for comorbidity
elixhauser_percentiles AS (
  SELECT
    APPROX_QUANTILES(elixhauser_count, 4)[OFFSET(3)] AS elixhauser_75th
  FROM cohort
),

-- 9. Final cohort: pneumonia, male, age 73–83, top quartile comorbidity
final_cohort AS (
  SELECT
    c.*,
    ep.elixhauser_75th
  FROM cohort c
  CROSS JOIN elixhauser_percentiles ep
  WHERE c.elixhauser_count >= ep.elixhauser_75th
),

-- 10. Major complication flag per admission
complication_flags AS (
  SELECT
    diag.hadm_id,
    COUNT(DISTINCT diag.icd_code) > 0 AS has_major_complication
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
  JOIN major_complication_icd mc
    ON diag.icd_code = mc.icd_code AND diag.icd_version = mc.icd_version
  GROUP BY diag.hadm_id
),

-- 11. Add complication flag to cohort
cohort_with_complications AS (
  SELECT
    fc.*,
    COALESCE(cf.has_major_complication, FALSE) AS has_major_complication
  FROM final_cohort fc
  LEFT JOIN complication_flags cf
    ON fc.hadm_id = cf.hadm_id
),

-- 12. Survival days calculation
survival_days AS (
  SELECT
    c.hadm_id,
    CASE
      WHEN c.dod IS NOT NULL AND c.dod >= c.admittime THEN DATE_DIFF(DATE(c.dod), DATE(c.admittime), DAY)
      ELSE DATE_DIFF(DATE(c.dischtime), DATE(c.admittime), DAY)
    END AS survival_days
  FROM cohort_with_complications c
),

-- 13. Composite risk score (simple sum: mortality + complication + inverse survival)
risk_scores AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.anchor_age,
    c.elixhauser_count,
    c.hospital_expire_flag,
    c.has_major_complication,
    s.survival_days,
    -- Composite risk: mortality (1), complication (1), inverse survival (1/survival_days)
    (CAST(c.hospital_expire_flag AS FLOAT64) +
     IF(c.has_major_complication, 1.0, 0.0) +
     IF(s.survival_days > 0, 1.0 / s.survival_days, 1.0)
    ) AS composite_risk
  FROM cohort_with_complications c
  JOIN survival_days s
    ON c.hadm_id = s.hadm_id
),

-- 14. Percentile ranking for index patient (78-year-old male)
index_patient AS (
  SELECT
    r.*,
    PERCENT_RANK() OVER (ORDER BY composite_risk) AS composite_risk_percentile
  FROM risk_scores r
  WHERE r.anchor_age = 78
),

-- 15. Cohort summary statistics
cohort_stats AS (
  SELECT
    COUNT(*) AS n_cohort,
    100.0 * SUM(CAST(hospital_expire_flag AS INT64)) / COUNT(*) AS mortality_pct,
    100.0 * SUM(CAST(has_major_complication AS INT64)) / COUNT(*) AS major_complication_pct,
    APPROX_QUANTILES(survival_days, 2)[OFFSET(1)] AS median_survival_days
  FROM risk_scores
)

-- Final output: cohort stats and index patient percentile
SELECT
  cs.n_cohort AS cohort_size,
  cs.mortality_pct AS in_hospital_mortality_pct,
  cs.major_complication_pct AS major_complication_pct,
  cs.median_survival_days,
  ip.composite_risk_percentile AS index_patient_composite_risk_percentile
FROM cohort_stats cs
LEFT JOIN index_patient ip
  ON TRUE
ORDER BY index_patient_composite_risk_percentile DESC
LIMIT 1;