WITH
-- base admissions for female patients aged 59-69
base_adm AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    COALESCE(a.deathtime, p.dod) AS death_time
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),

-- aggregate diagnoses per admission, derive PE flag, complication flags, and comorbidity score
diag_flags AS (
  SELECT
    di.hadm_id,
    -- proxy comorbidity score: number of distinct diagnosis ICD codes excluding any diagnosis whose label contains 'pulmonary embol'
    COUNT(DISTINCT CASE
      WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%pulmonary embol%' THEN NULL
      ELSE di.icd_code END) AS comorbidity_score,
    -- PE flag if any diagnosis label mentions pulmonary embol
    MAX(CASE WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%pulmonary embol%' THEN 1 ELSE 0 END) AS is_pe,
    -- Cardiac complication flag: look for common cardiac keywords
    MAX(CASE WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%myocard%'
                  OR LOWER(COALESCE(dd.long_title, '')) LIKE '%heart failure%'
                  OR LOWER(COALESCE(dd.long_title, '')) LIKE '%cardiac arrest%'
                  OR LOWER(COALESCE(dd.long_title, '')) LIKE '%arrhythmia%'
                  OR LOWER(COALESCE(dd.long_title, '')) LIKE '%atrial fibrillation%'
             THEN 1 ELSE 0 END) AS cardiac_comp,
    -- Neurologic complication flag: look for common neurologic keywords
    MAX(CASE WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%stroke%'
                  OR LOWER(COALESCE(dd.long_title, '')) LIKE '%cerebro%'
                  OR LOWER(COALESCE(dd.long_title, '')) LIKE '%intracranial%'
                  OR LOWER(COALESCE(dd.long_title, '')) LIKE '%seizure%'
                  OR LOWER(COALESCE(dd.long_title, '')) LIKE '%hemiplegia%'
             THEN 1 ELSE 0 END) AS neuro_comp
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  GROUP BY di.hadm_id
),

-- combine base admissions with diagnosis-derived flags
adm_with_flags AS (
  SELECT
    b.*,
    COALESCE(d.comorbidity_score, 0) AS comorbidity_score,
    COALESCE(d.is_pe, 0) AS is_pe,
    COALESCE(d.cardiac_comp, 0) AS cardiac_comp,
    COALESCE(d.neuro_comp, 0) AS neuro_comp,
    CASE
      WHEN COALESCE(d.comorbidity_score, 0) IS NULL THEN 0
      ELSE COALESCE(d.comorbidity_score, 0)
    END AS comorbidity_score_clean
  FROM base_adm b
  LEFT JOIN diag_flags d
    ON b.hadm_id = d.hadm_id
),

-- define death within 30 days of admission
adm_metrics AS (
  SELECT
    *,
    CASE
      WHEN death_time IS NOT NULL
       AND TIMESTAMP_DIFF(death_time, admittime, DAY) BETWEEN 0 AND 30 THEN 1
      ELSE 0
    END AS death_within_30d,
    -- treat LOS as 0 for missing dischtime (should be rare)
    COALESCE(los_days, 0) AS los_days_clean
  FROM adm_with_flags
),

-- PE admissions subset (same-age women)
pe_adm AS (
  SELECT * FROM adm_metrics WHERE is_pe = 1
),

-- control admissions: same-age female inpatients without PE
control_adm AS (
  SELECT * FROM adm_metrics WHERE is_pe = 0
),

-- determine high-comorbidity threshold among PE admissions: top quartile (>= 75th percentile)
pe_comorb_threshold AS (
  SELECT
    -- use approx quantiles for efficiency; offset 75 gives the 75th percentile
    APPROX_QUANTILES(comorbidity_score_clean, 100)[OFFSET(75)] AS q75
  FROM pe_adm
),

-- PE admissions with high comorbidity burden (>= q75)
pe_high AS (
  SELECT p.*
  FROM pe_adm p
  CROSS JOIN pe_comorb_threshold t
  WHERE p.comorbidity_score_clean >= t.q75
),

-- aggregated metrics function (cohort-level)
cohort_stats AS (
  SELECT
    'PE_high_comorbidity' AS cohort_label,
    COUNT(1) AS n_admissions,
    ROUND(AVG(comorbidity_score_clean), 3) AS mean_comorbidity_score,
    ROUND(100.0 * SUM(death_within_30d) / NULLIF(COUNT(1),0), 2) AS pct_30d_mortality,
    ROUND(100.0 * SUM(cardiac_comp) / NULLIF(COUNT(1),0), 2) AS pct_cardiac_complication,
    ROUND(100.0 * SUM(neuro_comp) / NULLIF(COUNT(1),0), 2) AS pct_neuro_complication,
    ROUND(AVG(CASE WHEN hospital_expire_flag = 0 THEN los_days_clean ELSE NULL END), 2) AS mean_survivor_los_days
  FROM pe_high

  UNION ALL

  SELECT
    'Controls_same_age_female_no_PE' AS cohort_label,
    COUNT(1) AS n_admissions,
    ROUND(AVG(comorbidity_score_clean), 3) AS mean_comorbidity_score,
    ROUND(100.0 * SUM(death_within_30d) / NULLIF(COUNT(1),0), 2) AS pct_30d_mortality,
    ROUND(100.0 * SUM(cardiac_comp) / NULLIF(COUNT(1),0), 2) AS pct_cardiac_complication,
    ROUND(100.0 * SUM(neuro_comp) / NULLIF(COUNT(1),0), 2) AS pct_neuro_complication,
    ROUND(AVG(CASE WHEN hospital_expire_flag = 0 THEN los_days_clean ELSE NULL END), 2) AS mean_survivor_los_days
  FROM control_adm
),

-- control distribution for computing percentiles
control_scores AS (
  SELECT comorbidity_score_clean AS comorbidity_score
  FROM control_adm
),

-- compute percentile of each PE high-comorbidity admission's comorbidity score within the control distribution,
-- then take the average percentile across PE high cohort
pe_vs_control_percentiles AS (
  SELECT
    p.hadm_id,
    p.comorbidity_score_clean AS pe_comorbidity_score,
    -- proportion of controls with score <= this PE score
    SAFE_DIVIDE(
      (SELECT COUNT(1) FROM control_scores c WHERE c.comorbidity_score <= p.comorbidity_score_clean),
      (SELECT COUNT(1) FROM control_scores)
    ) AS pctile_fraction
  FROM pe_high p
),

avg_percentile AS (
  SELECT
    ROUND(100.0 * AVG(COALESCE(pctile_fraction, 0)), 2) AS avg_percentile_of_pe_vs_controls
  FROM pe_vs_control_percentiles
)

-- Final output: cohort-level comparisons + average matched-profile percentile
SELECT
  cs.cohort_label,
  cs.n_admissions,
  cs.mean_comorbidity_score,
  cs.pct_30d_mortality,
  cs.pct_cardiac_complication,
  cs.pct_neuro_complication,
  cs.mean_survivor_los_days,
  ap.avg_percentile_of_pe_vs_controls
FROM cohort_stats cs
CROSS JOIN avg_percentile ap
ORDER BY cs.cohort_label;