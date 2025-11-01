WITH
-- distinct admissions that had any ICU stay
hadm_with_icu AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- base admissions joined to patients and restricted to female, age 67-77 and with ICU stay
adm_base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime AS adm_deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.hadm_id IN (SELECT hadm_id FROM hadm_with_icu)
),

-- aggregate diagnosis-based flags and diagnosis count per admission
diag_flags AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    COUNT(DISTINCT di.icd_code) AS diag_count,
    -- ACS: match common phrases in diagnosis description
    MAX(
      CASE
        WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%myocardial infarction%' THEN 1
        WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%acute coronary%' THEN 1
        WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%unstable angina%' THEN 1
        WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%acute myocardial%' THEN 1
        ELSE 0
      END
    ) AS any_acs,
    -- Cardiac complication: broad keyword-based flag
    MAX(
      CASE
        WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%cardi%' THEN 1
        WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%myocardial%' THEN 1
        WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%arrhythmia%' THEN 1
        WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%heart%' THEN 1
        ELSE 0
      END
    ) AS any_cardiac_comp,
    -- Neurologic complication: broad keyword-based flag
    MAX(
      CASE
        WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%stroke%' THEN 1
        WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%intracranial%' THEN 1
        WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%neurolog%' THEN 1
        WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%seizure%' THEN 1
        WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%brain%' THEN 1
        ELSE 0
      END
    ) AS any_neuro_comp
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  GROUP BY di.subject_id, di.hadm_id
),

-- combine base admissions with diagnosis-derived flags and compute derived metrics
adm_metrics AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.adm_deathtime,
    b.dod,
    b.hospital_expire_flag,
    b.anchor_age,
    COALESCE(df.diag_count, 0) AS risk_score_proxy,
    COALESCE(df.any_acs, 0) AS any_acs,
    COALESCE(df.any_cardiac_comp, 0) AS any_cardiac_comp,
    COALESCE(df.any_neuro_comp, 0) AS any_neuro_comp,
    -- 30-day mortality
    CASE
      WHEN COALESCE(b.adm_deathtime, b.dod) IS NOT NULL
           AND DATE_DIFF(DATE(COALESCE(b.adm_deathtime, b.dod)), DATE(b.admittime), DAY) BETWEEN 0 AND 30
        THEN 1 ELSE 0 END AS death_within_30d,
    -- survivor flag (in-hospital survivors)
    CASE WHEN b.hospital_expire_flag = 0 THEN 1 ELSE 0 END AS survivor_flag,
    -- LOS in days (use date diff; if dischtime null then NULL)
    CASE WHEN b.dischtime IS NOT NULL
         THEN DATE_DIFF(DATE(b.dischtime), DATE(b.admittime), DAY)
         ELSE NULL END AS los_days
  FROM adm_base b
  LEFT JOIN diag_flags df
    ON b.hadm_id = df.hadm_id
),

-- cohort-level aggregates for ACS and non-ACS cohorts (overall, across ages 67-77)
cohort_aggregates AS (
  SELECT
    any_acs_flag,
    COUNT(*) AS n_admissions,
    ROUND(AVG(risk_score_proxy), 3) AS mean_risk_score_proxy,
    ROUND(AVG(death_within_30d), 4) AS mortality_30d_rate,
    ROUND(AVG(any_cardiac_comp), 4) AS cardiac_complication_rate,
    ROUND(AVG(any_neuro_comp), 4) AS neuro_complication_rate,
    -- survivor mean LOS in days
    ROUND(
      AVG(CASE WHEN survivor_flag = 1 THEN los_days ELSE NULL END),
    3) AS survivor_mean_los_days
  FROM (
    SELECT
      CASE WHEN any_acs = 1 THEN 'ACS' ELSE 'NON_ACS' END AS any_acs_flag,
      risk_score_proxy,
      death_within_30d,
      any_cardiac_comp,
      any_neuro_comp,
      survivor_flag,
      los_days
    FROM adm_metrics
  )
  GROUP BY any_acs_flag
),

-- non-ACS per-age stats to build age-matched distribution (one row per age)
nonacs_age_stats AS (
  SELECT
    anchor_age,
    COUNT(*) AS n_adm,
    AVG(risk_score_proxy) AS mean_risk_score_proxy,
    AVG(death_within_30d) AS mortality_30d_rate,
    AVG(any_cardiac_comp) AS cardiac_complication_rate,
    AVG(any_neuro_comp) AS neuro_complication_rate,
    AVG(CASE WHEN survivor_flag = 1 THEN los_days ELSE NULL END) AS survivor_mean_los_days
  FROM adm_metrics
  WHERE any_acs = 0
  GROUP BY anchor_age
  HAVING COUNT(*) >= 1
),

-- ACS overall metrics (single row) for percentile comparisons
acs_overall AS (
  SELECT
    AVG(risk_score_proxy) AS mean_risk_score_proxy,
    AVG(death_within_30d) AS mortality_30d_rate,
    AVG(any_cardiac_comp) AS cardiac_complication_rate,
    AVG(any_neuro_comp) AS neuro_complication_rate,
    AVG(CASE WHEN survivor_flag = 1 THEN los_days ELSE NULL END) AS survivor_mean_los_days
  FROM adm_metrics
  WHERE any_acs = 1
)

-- final selection: cohort aggregates plus percentile comparison of ACS overall vs age-matched non-ACS distribution
SELECT
  -- Cohort aggregate rows (ACS and NON-ACS)
  ca.any_acs_flag AS cohort_label,
  ca.n_admissions,
  ca.mean_risk_score_proxy,
  ca.mortality_30d_rate,
  ca.cardiac_complication_rate,
  ca.neuro_complication_rate,
  ca.survivor_mean_los_days,
  -- Percentile of the ACS overall metrics among the per-age non-ACS distribution (values between 0 and 1).
  -- For NON-ACS row we set percentiles to NULL; for ACS row we compute percentiles versus nonacs_age_stats.
  CASE
    WHEN ca.any_acs_flag = 'ACS' THEN
      SAFE_DIVIDE(SUM(CASE WHEN nas.mean_risk_score_proxy <= ao.mean_risk_score_proxy THEN 1 ELSE 0 END), COUNT(nas.anchor_age))
    ELSE NULL END AS percentile_vs_age_matched_mean_risk_score_proxy,
  CASE
    WHEN ca.any_acs_flag = 'ACS' THEN
      SAFE_DIVIDE(SUM(CASE WHEN nas.mortality_30d_rate <= ao.mortality_30d_rate THEN 1 ELSE 0 END), COUNT(nas.anchor_age))
    ELSE NULL END AS percentile_vs_age_matched_mortality_30d_rate,
  CASE
    WHEN ca.any_acs_flag = 'ACS' THEN
      SAFE_DIVIDE(SUM(CASE WHEN nas.cardiac_complication_rate <= ao.cardiac_complication_rate THEN 1 ELSE 0 END), COUNT(nas.anchor_age))
    ELSE NULL END AS percentile_vs_age_matched_cardiac_rate,
  CASE
    WHEN ca.any_acs_flag = 'ACS' THEN
      SAFE_DIVIDE(SUM(CASE WHEN nas.neuro_complication_rate <= ao.neuro_complication_rate THEN 1 ELSE 0 END), COUNT(nas.anchor_age))
    ELSE NULL END AS percentile_vs_age_matched_neuro_rate,
  CASE
    WHEN ca.any_acs_flag = 'ACS' THEN
      SAFE_DIVIDE(SUM(CASE WHEN nas.survivor_mean_los_days <= ao.survivor_mean_los_days THEN 1 ELSE 0 END), COUNT(nas.anchor_age))
    ELSE NULL END AS percentile_vs_age_matched_survivor_mean_los_days
FROM cohort_aggregates ca
LEFT JOIN nonacs_age_stats nas ON TRUE  -- cross-join to allow counting age-level rows
LEFT JOIN acs_overall ao ON TRUE
GROUP BY ca.any_acs_flag, ca.n_admissions, ca.mean_risk_score_proxy, ca.mortality_30d_rate, ca.cardiac_complication_rate, ca.neuro_complication_rate, ca.survivor_mean_los_days
ORDER BY CASE WHEN ca.any_acs_flag = 'ACS' THEN 0 ELSE 1 END;