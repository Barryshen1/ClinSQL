WITH
-- 1. Female inpatients aged 68-78
base_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),

-- 2. HHS admissions (ICD codes for HHS)
hhs_admissions AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (
      (icd_version = 10 AND icd_code IN ('E11.0', 'E13.0', 'E08.0', 'E09.0', 'E10.0'))
      OR
      (icd_version = 9 AND icd_code IN ('250.2', '250.20', '250.22')) -- ICD-9 for HHS
    )
),

-- 3. Cohorts
target_cohort AS (
  SELECT bp.*
  FROM base_patients bp
  JOIN hhs_admissions hhs
    ON bp.subject_id = hhs.subject_id AND bp.hadm_id = hhs.hadm_id
),
comparison_cohort AS (
  SELECT *
  FROM base_patients
),

-- 4. Hyperkalemia-risk drugs (lower-case for matching)
hyperk_drugs AS (
  SELECT DISTINCT LOWER(drug) AS drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%spironolactone%' OR
    LOWER(drug) LIKE '%eplerenone%' OR
    LOWER(drug) LIKE '%amiloride%' OR
    LOWER(drug) LIKE '%triamterene%' OR
    LOWER(drug) LIKE '%ace inhibitor%' OR
    LOWER(drug) LIKE '%lisinopril%' OR
    LOWER(drug) LIKE '%enalapril%' OR
    LOWER(drug) LIKE '%ramipril%' OR
    LOWER(drug) LIKE '%captopril%' OR
    LOWER(drug) LIKE '%arb%' OR
    LOWER(drug) LIKE '%losartan%' OR
    LOWER(drug) LIKE '%valsartan%' OR
    LOWER(drug) LIKE '%irbesartan%' OR
    LOWER(drug) LIKE '%olmesartan%' OR
    LOWER(drug) LIKE '%telmisartan%' OR
    LOWER(drug) LIKE '%potassium%' OR
    LOWER(drug) LIKE '%nsaid%' OR
    LOWER(drug) LIKE '%ibuprofen%' OR
    LOWER(drug) LIKE '%naproxen%' OR
    LOWER(drug) LIKE '%diclofenac%' OR
    LOWER(drug) LIKE '%celecoxib%' OR
    LOWER(drug) LIKE '%indomethacin%'
),

-- 5. Medication complexity and hyperkalemia-risk exposure per admission
med_complex AS (
  SELECT
    bp.subject_id,
    bp.hadm_id,
    COUNT(DISTINCT LOWER(pr.drug)) AS med_complexity,
    COUNT(DISTINCT CASE WHEN hk.drug IS NOT NULL THEN LOWER(pr.drug) END) AS hyperk_drug_count
  FROM
    base_patients bp
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON bp.subject_id = pr.subject_id
      AND bp.hadm_id = pr.hadm_id
      AND pr.starttime >= bp.admittime
      AND pr.starttime < DATETIME_ADD(bp.admittime, INTERVAL 72 HOUR)
    LEFT JOIN hyperk_drugs hk
      ON LOWER(pr.drug) = hk.drug
  GROUP BY
    bp.subject_id, bp.hadm_id
),

-- 6. Add LOS and mortality
med_complex_full AS (
  SELECT
    mc.*,
    DATETIME_DIFF(bp.dischtime, bp.admittime, DAY) AS los,
    bp.hospital_expire_flag
  FROM
    med_complex mc
    JOIN base_patients bp
      ON mc.subject_id = bp.subject_id AND mc.hadm_id = bp.hadm_id
),

-- 7. Percentile rank of medication complexity
med_complex_percentile AS (
  SELECT
    subject_id,
    hadm_id,
    med_complexity,
    hyperk_drug_count,
    los,
    hospital_expire_flag,
    PERCENT_RANK() OVER (ORDER BY med_complexity) AS med_complexity_percentile
  FROM
    med_complex_full
),

-- 8. Target cohort stats: compute quartile threshold and median percentile for hyperk patients
target_stats AS (
  SELECT
    APPROX_QUANTILES(med_complexity, 10) AS med_complexity_deciles,
    APPROX_QUANTILES(los, 4) AS los_quartiles,
    APPROX_QUANTILES(med_complexity_percentile, 2)[OFFSET(1)] AS median_percentile_all,
    -- For hyperk patients (>=2 drugs), median percentile
    APPROX_QUANTILES(med_complexity_percentile, 2)[OFFSET(1)] AS median_percentile_hyperk,
    APPROX_QUANTILES(los, 4)[OFFSET(3)] AS los_top_quartile_threshold
  FROM
    med_complex_percentile mcp
  WHERE EXISTS (
    SELECT 1 FROM target_cohort tc
    WHERE tc.subject_id = mcp.subject_id
      AND tc.hadm_id = mcp.hadm_id
  )
),

-- 9. Comparison cohort stats
comparison_stats AS (
  SELECT
    APPROX_QUANTILES(med_complexity, 10) AS med_complexity_deciles,
    APPROX_QUANTILES(los, 4) AS los_quartiles,
    APPROX_QUANTILES(med_complexity_percentile, 2)[OFFSET(1)] AS median_percentile_all,
    -- For hyperk patients (>=2 drugs), median percentile
    APPROX_QUANTILES(med_complexity_percentile, 2)[OFFSET(1)] AS median_percentile_hyperk,
    APPROX_QUANTILES(los, 4)[OFFSET(3)] AS los_top_quartile_threshold
  FROM
    med_complex_percentile mcp
  WHERE EXISTS (
    SELECT 1 FROM comparison_cohort cc
    WHERE cc.subject_id = mcp.subject_id
      AND cc.hadm_id = mcp.hadm_id
  )
),

-- 10. Target cohort summary
target_summary AS (
  SELECT
    'target' AS cohort,
    COUNT(*) AS n_patients,
    ts.med_complexity_deciles AS med_complexity_deciles,
    ts.los_quartiles AS los_quartiles,
    SUM(CASE WHEN hyperk_drug_count >= 2 THEN 1 ELSE 0 END) AS n_hyperk,
    SAFE_DIVIDE(SUM(CASE WHEN hyperk_drug_count >= 2 THEN 1 ELSE 0 END), COUNT(*)) AS pct_hyperk,
    -- Median percentile for hyperk patients
    (
      SELECT APPROX_QUANTILES(med_complexity_percentile, 2)[OFFSET(1)]
      FROM med_complex_percentile mcp2
      WHERE EXISTS (
        SELECT 1 FROM target_cohort tc2
        WHERE tc2.subject_id = mcp2.subject_id
          AND tc2.hadm_id = mcp2.hadm_id
      )
      AND mcp2.hyperk_drug_count >= 2
    ) AS median_percentile_hyperk,
    SUM(CASE WHEN los >= ts.los_top_quartile_threshold THEN 1 ELSE 0 END) AS n_top_quartile_los,
    SAFE_DIVIDE(SUM(CASE WHEN los >= ts.los_top_quartile_threshold THEN 1 ELSE 0 END), COUNT(*)) AS pct_top_quartile_los,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_mortality,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS pct_mortality
  FROM
    med_complex_percentile mcp
    CROSS JOIN target_stats ts
  WHERE EXISTS (
    SELECT 1 FROM target_cohort tc
    WHERE tc.subject_id = mcp.subject_id
      AND tc.hadm_id = mcp.hadm_id
  )
),

-- 11. Comparison cohort summary
comparison_summary AS (
  SELECT
    'comparison' AS cohort,
    COUNT(*) AS n_patients,
    cs.med_complexity_deciles AS med_complexity_deciles,
    cs.los_quartiles AS los_quartiles,
    SUM(CASE WHEN hyperk_drug_count >= 2 THEN 1 ELSE 0 END) AS n_hyperk,
    SAFE_DIVIDE(SUM(CASE WHEN hyperk_drug_count >= 2 THEN 1 ELSE 0 END), COUNT(*)) AS pct_hyperk,
    (
      SELECT APPROX_QUANTILES(med_complexity_percentile, 2)[OFFSET(1)]
      FROM med_complex_percentile mcp2
      WHERE EXISTS (
        SELECT 1 FROM comparison_cohort cc2
        WHERE cc2.subject_id = mcp2.subject_id
          AND cc2.hadm_id = mcp2.hadm_id
      )
      AND mcp2.hyperk_drug_count >= 2
    ) AS median_percentile_hyperk,
    SUM(CASE WHEN los >= cs.los_top_quartile_threshold THEN 1 ELSE 0 END) AS n_top_quartile_los,
    SAFE_DIVIDE(SUM(CASE WHEN los >= cs.los_top_quartile_threshold THEN 1 ELSE 0 END), COUNT(*)) AS pct_top_quartile_los,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_mortality,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS pct_mortality
  FROM
    med_complex_percentile mcp
    CROSS JOIN comparison_stats cs
  WHERE EXISTS (
    SELECT 1 FROM comparison_cohort cc
    WHERE cc.subject_id = mcp.subject_id
      AND cc.hadm_id = mcp.hadm_id
  )
)

SELECT * FROM target_summary
UNION ALL
SELECT * FROM comparison_summary;