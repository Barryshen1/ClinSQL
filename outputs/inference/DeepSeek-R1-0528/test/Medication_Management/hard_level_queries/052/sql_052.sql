WITH admissions_with_age AS (
  SELECT 
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
    p.gender, 
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),

hhs_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND icd_code IN ('E110', 'E111', 'E130', 'E131')) OR
    (icd_version = 9 AND icd_code LIKE '250.2%')
),

cohort_a AS (
  SELECT 
    a.*, 
    'A' AS cohort_name  -- HHS group
  FROM admissions_with_age a
  WHERE 
    a.gender = 'F' 
    AND a.age_adm BETWEEN 68 AND 78
    AND a.hadm_id IN (SELECT hadm_id FROM hhs_admissions)
),

cohort_b AS (
  SELECT 
    *, 
    'B' AS cohort_name  -- All inpatients
  FROM admissions_with_age
),

all_cohorts AS (
  SELECT * FROM cohort_a
  UNION ALL
  SELECT * FROM cohort_b
),

meds_emar AS (
  SELECT 
    e.hadm_id, 
    e.medication AS drug_name
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  INNER JOIN admissions_with_age a 
    ON e.hadm_id = a.hadm_id
  WHERE e.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
),

meds_input AS (
  SELECT 
    i.hadm_id, 
    d.label AS drug_name
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  INNER JOIN admissions_with_age a 
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
    ON i.itemid = d.itemid
  WHERE i.starttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
),

all_meds AS (
  SELECT hadm_id, drug_name FROM meds_emar
  UNION DISTINCT
  SELECT hadm_id, drug_name FROM meds_input
),

med_complexity AS (
  SELECT 
    hadm_id, 
    COUNT(DISTINCT drug_name) AS med_count
  FROM all_meds
  GROUP BY hadm_id
),

hyperkalemia_drugs AS (
  SELECT 
    hadm_id,
    MAX(
      CASE 
        WHEN 
          LOWER(drug_name) LIKE '%potassium%' OR
          LOWER(drug_name) LIKE '%spironolactone%' OR 
          LOWER(drug_name) LIKE '%triamterene%' OR 
          LOWER(drug_name) LIKE '%amiloride%' OR
          LOWER(drug_name) LIKE '%captopril%' OR 
          LOWER(drug_name) LIKE '%enalapril%' OR 
          LOWER(drug_name) LIKE '%lisinopril%' OR 
          LOWER(drug_name) LIKE '%ramipril%' OR 
          LOWER(drug_name) LIKE '%losartan%' OR 
          LOWER(drug_name) LIKE '%valsartan%' OR 
          LOWER(drug_name) LIKE '%ibuprofen%' OR 
          LOWER(drug_name) LIKE '%naproxen%' OR 
          LOWER(drug_name) LIKE '%diclofenac%' OR 
          LOWER(drug_name) LIKE '%heparin%' OR 
          LOWER(drug_name) LIKE '%trimethoprim%' OR 
          LOWER(drug_name) LIKE '%cyclosporine%' OR 
          LOWER(drug_name) LIKE '%tacrolimus%' 
        THEN 1 
        ELSE 0 
      END
    ) AS hyper_flag
  FROM all_meds
  GROUP BY hadm_id
),

cohort_data AS (
  SELECT 
    c.*,
    COALESCE(m.med_count, 0) AS med_count,
    COALESCE(h.hyper_flag, 0) AS hyper_flag,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM all_cohorts c
  LEFT JOIN med_complexity m 
    ON c.hadm_id = m.hadm_id
  LEFT JOIN hyperkalemia_drugs h 
    ON c.hadm_id = h.hadm_id
),

hyperkalemia_ranks AS (
  SELECT 
    hadm_id,
    hyper_flag,
    PERCENT_RANK() OVER (ORDER BY hyper_flag) * 100 AS percentile_rank
  FROM cohort_data
  WHERE cohort_name = 'B'  -- Rank relative to all inpatients
),

final_data AS (
  SELECT 
    cd.*,
    hr.percentile_rank
  FROM cohort_data cd
  LEFT JOIN hyperkalemia_ranks hr 
    ON cd.hadm_id = hr.hadm_id
)

SELECT 
  cohort_name,
  -- Medication complexity distribution (25th, 50th, 75th percentiles)
  APPROX_QUANTILES(med_count, 100)[OFFSET(25)] AS med_count_p25,
  APPROX_QUANTILES(med_count, 100)[OFFSET(50)] AS med_count_median,
  APPROX_QUANTILES(med_count, 100)[OFFSET(75)] AS med_count_p75,
  -- Median percentile rank for hyperkalemia-risk
  APPROX_QUANTILES(percentile_rank, 100)[OFFSET(50)] AS hyperkalemia_median_percentile_rank,
  -- Percent with hyperkalemia-risk drugs
  100.0 * SUM(hyper_flag) / COUNT(*) AS hyperkalemia_percent_affected,
  -- Top-quartile LOS (75th percentile)
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_p75,
  -- Mortality rate (%)
  100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM final_data
GROUP BY cohort_name;