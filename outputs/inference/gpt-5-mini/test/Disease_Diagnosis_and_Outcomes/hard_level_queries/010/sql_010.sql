WITH
-- Aggregate diagnoses per hospital admission to derive DKA flag, complication flags, and a comorbidity count proxy
dx_by_hadm AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    -- DKA flag based on diagnosis description text
    MAX(
      CASE
        WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%ketoacido%' OR LOWER(COALESCE(dd.long_title, '')) LIKE '%ketoacidosis%' THEN 1
        ELSE 0
      END
    ) AS is_dka,
    -- cardiovascular complication flag (keyword-based)
    MAX(
      CASE
        WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%myocard%' OR
             LOWER(COALESCE(dd.long_title, '')) LIKE '%cardiac%' OR
             LOWER(COALESCE(dd.long_title, '')) LIKE '%coronar%' OR
             LOWER(COALESCE(dd.long_title, '')) LIKE '%ischem%' OR
             LOWER(COALESCE(dd.long_title, '')) LIKE '%infarct%' OR
             LOWER(COALESCE(dd.long_title, '')) LIKE '%arrhythm%' OR
             LOWER(COALESCE(dd.long_title, '')) LIKE '%heart %'
        THEN 1 ELSE 0
      END
    ) AS has_cardiovascular_dx,
    -- neurologic complication flag (keyword-based)
    MAX(
      CASE
        WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%stroke%' OR
             LOWER(COALESCE(dd.long_title, '')) LIKE '%cerebro%' OR
             LOWER(COALESCE(dd.long_title, '')) LIKE '%seizur%' OR
             LOWER(COALESCE(dd.long_title, '')) LIKE '%encephal%' OR
             LOWER(COALESCE(dd.long_title, '')) LIKE '%neurop%' OR
             LOWER(COALESCE(dd.long_title, '')) LIKE '%paralysis%' OR
             LOWER(COALESCE(dd.long_title, '')) LIKE '%intracran%'
        THEN 1 ELSE 0
      END
    ) AS has_neurologic_dx,
    -- Comorbidity count proxy: distinct 3-char ICD prefixes, excluding DKA diagnoses
    COUNT(DISTINCT
      CASE
        WHEN NOT (
          LOWER(COALESCE(dd.long_title, '')) LIKE '%ketoacido%' OR
          LOWER(COALESCE(dd.long_title, '')) LIKE '%ketoacidosis%'
        )
        THEN SUBSTR(d.icd_code,1,3)
        ELSE NULL
      END
    ) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  GROUP BY
    d.subject_id, d.hadm_id
),

-- Build admissions with patient and diagnosis-derived flags
admissions_with_dx AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime AS adm_deathtime,
    p.dod AS patient_dod,
    COALESCE(dx.is_dka, 0) AS is_dka,
    COALESCE(dx.has_cardiovascular_dx, 0) AS has_cardiovascular_dx,
    COALESCE(dx.has_neurologic_dx, 0) AS has_neurologic_dx,
    COALESCE(dx.comorbidity_count, 0) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    LEFT JOIN dx_by_hadm dx
      ON a.hadm_id = dx.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),

-- Compute per-admission derived outcomes (30-day death, LOS days)
adm_outcomes AS (
  SELECT
    *,
    -- Use the earliest available death time (admission-level deathtime, otherwise patient DOD)
    SAFE_CAST(
      COALESCE(adm_deathtime, patient_dod) AS TIMESTAMP
    ) AS first_death_time,
    -- death within 30 days of admission
    CASE
      WHEN COALESCE(adm_deathtime, patient_dod) IS NOT NULL
       AND TIMESTAMP_DIFF(COALESCE(adm_deathtime, patient_dod), admittime, DAY) BETWEEN 0 AND 30
      THEN 1 ELSE 0
    END AS death_within_30d,
    -- LOS in fractional days (dischtime - admittime). If dischtime is null, leave null.
    CASE
      WHEN dischtime IS NOT NULL THEN TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0
      ELSE NULL
    END AS los_days
  FROM
    admissions_with_dx
),

-- Aggregate metrics for DKA subgroup and for all males 39-49
group_metrics AS (
  SELECT
    CASE WHEN is_dka = 1 THEN 'DKA_males_39_49' ELSE 'All_males_39_49' END AS cohort,
    COUNT(*) AS n_admissions,
    AVG(comorbidity_count) AS mean_risk_score,
    SUM(CASE WHEN death_within_30d = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS mortality_30d_rate,
    SUM(CASE WHEN has_cardiovascular_dx = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS cardiovascular_complication_rate,
    SUM(CASE WHEN has_neurologic_dx = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS neurologic_complication_rate,
    -- mean LOS among survivors to 30 days (i.e., death_within_30d = 0)
    AVG(CASE WHEN death_within_30d = 0 THEN los_days ELSE NULL END) AS mean_survivor_los_days
  FROM
    adm_outcomes
  GROUP BY
    is_dka
),

-- Compute the "matched profile" risk (mean comorbidity_count for male, age=44, with DKA)
profile_risk AS (
  SELECT
    AVG(comorbidity_count) AS profile_mean_risk
  FROM
    adm_outcomes
  WHERE
    anchor_age = 44
    AND is_dka = 1
),

-- Compute percentile of that profile_mean_risk among all male 39-49 admissions' comorbidity_count distribution
risk_percentile AS (
  SELECT
    pr.profile_mean_risk,
    CASE
      WHEN pr.profile_mean_risk IS NULL THEN NULL
      ELSE 100.0 * SAFE_DIVIDE(
             SUM(CASE WHEN a.comorbidity_count <= pr.profile_mean_risk THEN 1 ELSE 0 END),
             COUNT(*)
           )
    END AS percentile_among_males_39_49
  FROM
    profile_risk pr
    CROSS JOIN adm_outcomes a
  GROUP BY
    pr.profile_mean_risk
)

-- Final combined output: group metrics (DKA vs all) plus the risk percentile for the 44-year-old DKA profile
SELECT
  gm.cohort,
  gm.n_admissions,
  ROUND(gm.mean_risk_score, 3) AS mean_risk_score_comorbidity_count_proxy,
  ROUND(gm.mortality_30d_rate * 100, 2) AS mortality_30d_percent,
  ROUND(gm.cardiovascular_complication_rate * 100, 2) AS cardiovascular_complication_percent,
  ROUND(gm.neurologic_complication_rate * 100, 2) AS neurologic_complication_percent,
  ROUND(gm.mean_survivor_los_days, 2) AS mean_survivor_los_days,
  -- attach profile percentile (same value for both rows; null if profile not present)
  ROUND(rp.percentile_among_males_39_49, 2) AS profile_risk_percentile_among_males_39_49
FROM
  group_metrics gm
  CROSS JOIN risk_percentile rp
ORDER BY
  -- put DKA row first
  CASE WHEN gm.cohort = 'DKA_males_39_49' THEN 0 ELSE 1 END;