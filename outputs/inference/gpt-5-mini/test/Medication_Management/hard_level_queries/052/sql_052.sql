WITH
-- 1) Identify HHS admissions (by diagnosis description or ICD9 pattern 250.2x)
hhs_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dict
    ON d.icd_code = dict.icd_code AND d.icd_version = dict.icd_version
  WHERE (
    LOWER(COALESCE(dict.long_title, '')) LIKE '%hyperosmolar%'
    OR (d.icd_version = 9 AND d.icd_code LIKE '250.2%')
  )
),

-- 2) All hospital medication orders (prescriptions + pharmacy) normalized to have hadm_id, starttime, drug
hospital_meds AS (
  SELECT hadm_id, starttime, LOWER(TRIM(COALESCE(drug, ''))) AS drug_name
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE starttime IS NOT NULL AND drug IS NOT NULL

  UNION ALL

  SELECT hadm_id, starttime, LOWER(TRIM(COALESCE(medication, ''))) AS drug_name
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE starttime IS NOT NULL AND medication IS NOT NULL
),

-- 3) Admissions expanded with patient info and cohort label
admissions_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- Cohort labeling: HHS female 68-78 vs all inpatients
    CASE
      WHEN a.hadm_id IN (SELECT hadm_id FROM hhs_hadm)
       AND p.gender = 'F'
       AND p.anchor_age BETWEEN 68 AND 78 THEN 'HHS_female_68_78'
      ELSE 'All_inpatients'
    END AS cohort_label
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p USING (subject_id)
),

-- 4) For each admission compute meds in first 72 hours and flags for risk drug classes
hadm_med_summary AS (
  -- start with admissions_cohort rows (include all admissions; meds may be zero)
  SELECT
    ac.hadm_id,
    ac.cohort_label,
    ac.admittime,
    ac.dischtime,
    ac.hospital_expire_flag,
    -- LOS in hours
    SAFE_CAST(TIMESTAMP_DIFF(ac.dischtime, ac.admittime, HOUR) AS INT64) AS los_hours,
    -- medication complexity: count distinct drug names given in first 72 hours
    COUNT(DISTINCT CASE WHEN hm.starttime BETWEEN ac.admittime AND TIMESTAMP_ADD(ac.admittime, INTERVAL 72 HOUR)
                        THEN hm.drug_name END) AS med_complexity,
    -- presence flags for drug classes within first 72 hours (0/1)
    MAX(CASE WHEN REGEXP_CONTAINS(COALESCE(hm.drug_name,''), r'(lisinopril|enalapril|ramipril|captopril|benazepril|perindopril|quinapril|fosinopril|trandolapril|moexipril|losartan|valsartan|irbesartan|candesartan|olmesartan)') 
             AND hm.starttime BETWEEN ac.admittime AND TIMESTAMP_ADD(ac.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS has_raas,
    MAX(CASE WHEN REGEXP_CONTAINS(COALESCE(hm.drug_name,''), r'(spironolactone|eplerenone|amiloride|triamterene)') 
             AND hm.starttime BETWEEN ac.admittime AND TIMESTAMP_ADD(ac.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS has_k_sparing,
    MAX(CASE WHEN REGEXP_CONTAINS(COALESCE(hm.drug_name,''), r'(\bkcl\b|potassium chloride|(^|[^a-z])potassium([^a-z]|$))') 
             AND hm.starttime BETWEEN ac.admittime AND TIMESTAMP_ADD(ac.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS has_potassium_supp,
    MAX(CASE WHEN REGEXP_CONTAINS(COALESCE(hm.drug_name,''), r'(trimethoprim|sulfamethoxazole|bactrim|septra)') 
             AND hm.starttime BETWEEN ac.admittime AND TIMESTAMP_ADD(ac.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS has_tmp_smx
  FROM admissions_cohort ac
  LEFT JOIN hospital_meds hm
    ON ac.hadm_id = hm.hadm_id
  GROUP BY ac.hadm_id, ac.cohort_label, ac.admittime, ac.dischtime, ac.hospital_expire_flag
),

-- 5) Flag interactions and compute percentile rank per cohort
hadm_with_flags AS (
  SELECT
    h.*,
    -- Define an interaction: co-occurrence of two (or more) high-risk classes within the 72h window.
    CASE
      WHEN (has_raas = 1 AND (has_potassium_supp = 1 OR has_k_sparing = 1 OR has_tmp_smx = 1)) THEN 1
      WHEN (has_k_sparing = 1 AND has_potassium_supp = 1) THEN 1
      WHEN (has_tmp_smx = 1 AND has_raas = 1) THEN 1
      ELSE 0
    END AS hyperk_interaction_flag
  FROM hadm_med_summary h
),

-- 6) Compute percentile rank of med_complexity within each cohort and mark top-quartile LOS threshold
hadm_percentiles AS (
  SELECT
    hwf.*,
    -- percent rank within cohort based on med_complexity (0..1)
    PERCENT_RANK() OVER (PARTITION BY cohort_label ORDER BY med_complexity) AS med_complexity_pct_rank
  FROM hadm_with_flags hwf
),

-- 7a) Per-cohort summary metrics (no correlated subqueries)
cohort_base AS (
  SELECT
    cohort_label,
    COUNT(*) AS cohort_n,
    COUNTIF(med_complexity BETWEEN 0 AND 4) AS bin_0_4_n,
    COUNTIF(med_complexity BETWEEN 5 AND 9) AS bin_5_9_n,
    COUNTIF(med_complexity BETWEEN 10 AND 14) AS bin_10_14_n,
    COUNTIF(med_complexity >= 15) AS bin_15p_n,
    100.0 * SAFE_DIVIDE(SUM(hyperk_interaction_flag), COUNT(*)) AS pct_with_hyperk_interaction,
    -- median percentile rank among affected (approximate via APPROX_QUANTILES with 101 slices -> index 50)
    APPROX_QUANTILES(CASE WHEN hyperk_interaction_flag = 1 THEN med_complexity_pct_rank ELSE NULL END, 101)[OFFSET(50)] AS median_pct_rank_of_affected,
    -- top-quartile LOS threshold (75th percentile)
    APPROX_QUANTILES(los_hours, 4)[OFFSET(3)] AS los_hours_75th
  FROM hadm_percentiles
  GROUP BY cohort_label
),

-- 7b) Mortality among top-quartile LOS patients per cohort (join to cohort_base to use the precomputed threshold)
cohort_mortality AS (
  SELECT
    hp.cohort_label,
    100.0 * SAFE_DIVIDE(SUM(hp.hospital_expire_flag), NULLIF(COUNT(hp.hadm_id), 0)) AS pct_mortality_top_quartile_loS
  FROM hadm_percentiles hp
  JOIN cohort_base cb
    ON hp.cohort_label = cb.cohort_label
  WHERE hp.los_hours >= cb.los_hours_75th
  GROUP BY hp.cohort_label
)

-- Final select: expand distribution bins into rows for readability per cohort
SELECT
  cb.cohort_label,
  cb.cohort_n,
  STRUCT('0-4' AS bin, cb.bin_0_4_n AS n, ROUND(100.0 * SAFE_DIVIDE(cb.bin_0_4_n, cb.cohort_n), 3) AS pct) AS bin_0_4,
  STRUCT('5-9' AS bin, cb.bin_5_9_n AS n, ROUND(100.0 * SAFE_DIVIDE(cb.bin_5_9_n, cb.cohort_n), 3) AS pct) AS bin_5_9,
  STRUCT('10-14' AS bin, cb.bin_10_14_n AS n, ROUND(100.0 * SAFE_DIVIDE(cb.bin_10_14_n, cb.cohort_n), 3) AS pct) AS bin_10_14,
  STRUCT('15+' AS bin, cb.bin_15p_n AS n, ROUND(100.0 * SAFE_DIVIDE(cb.bin_15p_n, cb.cohort_n), 3) AS pct) AS bin_15p,
  -- Percent affected
  ROUND(cb.pct_with_hyperk_interaction, 3) AS pct_with_hyperk_interaction,
  -- Median percentile rank among affected
  SAFE_CAST(cb.median_pct_rank_of_affected AS FLOAT64) AS median_pct_rank_of_affected,
  -- Top-quartile LOS threshold and mortality among top quartile
  cb.los_hours_75th,
  ROUND(COALESCE(cm.pct_mortality_top_quartile_loS, 0.0), 3) AS pct_mortality_top_quartile_loS

FROM cohort_base cb
LEFT JOIN cohort_mortality cm USING (cohort_label)
ORDER BY cb.cohort_label;