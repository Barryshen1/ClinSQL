WITH admissions_with_pneumonia AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    USING(subject_id, hadm_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 48 AND 58
    AND LOWER(d.long_title) LIKE '%pneumonia%'
),
-- medications within first 24 hours of admission (prescriptions)
meds_first_24h AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT COALESCE(pr.drug, pr.formulary_drug_cd)) AS med_count,
    -- flag if any med name matches common serotonergic agents (heuristic name matching)
    MAX(
      CASE
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%sertraline%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%fluoxetine%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%paroxetine%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%citalopram%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%escitalopram%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%fluvoxamine%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%venlafaxine%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%duloxetine%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%tramadol%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%meperidine%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%linezolid%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%sumatriptan%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%rizatriptan%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%zolmitriptan%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%ergotamine%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%methadone%' THEN 1
        WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%mirtazapine%' THEN 1
        ELSE 0
      END
    ) AS serotonergic_flag
  FROM
    admissions_with_pneumonia a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.hadm_id = pr.hadm_id
  WHERE
    pr.starttime IS NOT NULL
    -- include prescriptions that start on or after admittime and within 24 hours
    AND pr.starttime >= a.admittime
    AND pr.starttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
  GROUP BY
    a.hadm_id
),
-- combine cohort info, compute LOS in days, ICU flag
cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400) AS los_days,
    a.hospital_expire_flag AS died_in_hosp,
    m.med_count,
    m.serotonergic_flag,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
      WHERE ic.hadm_id = a.hadm_id
    ) THEN 1 ELSE 0 END AS icu_flag
  FROM
    admissions_with_pneumonia a
  JOIN
    meds_first_24h m
    USING(hadm_id)  -- only keep admissions that had meds in first 24h
),
-- overall medication complexity distribution across the cohort
med_complexity_stats AS (
  SELECT
    COUNT(1) AS n_admissions,
    ROUND(AVG(med_count),3) AS mean_med_count,
    APPROX_QUANTILES(med_count, 4) AS med_count_quartiles  -- returns [min, Q1, median, Q3, max]
  FROM
    cohort
),
-- per-group metrics for serotonergic-risk and ICU groups
group_base AS (
  SELECT
    hadm_id,
    los_days,
    died_in_hosp,
    med_count,
    serotonergic_flag,
    icu_flag
  FROM
    cohort
),
-- compute group-level quartile (Q3) and base metrics
group_q3 AS (
  SELECT
    'serotonergic' AS group_name,
    AVG(los_days) AS mean_los,
    COUNT(1) AS n_adm,
    SUM(died_in_hosp) AS n_deaths,
    SAFE_DIVIDE(SUM(died_in_hosp), COUNT(1)) AS mortality_rate,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS los_q3
  FROM group_base
  WHERE serotonergic_flag = 1

  UNION ALL

  SELECT
    'icu' AS group_name,
    AVG(los_days) AS mean_los,
    COUNT(1) AS n_adm,
    SUM(died_in_hosp) AS n_deaths,
    SAFE_DIVIDE(SUM(died_in_hosp), COUNT(1)) AS mortality_rate,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS los_q3
  FROM group_base
  WHERE icu_flag = 1
),
-- compute mortality within each group's top-quartile LOS (LOS >= group's Q3)
group_top_quartile_stats AS (
  SELECT
    g.group_name,
    g.n_adm,
    ROUND(g.mean_los,3) AS mean_los_days,
    ROUND(g.mortality_rate,4) AS mortality_rate_overall,
    ROUND(g.los_q3,3) AS los_q3_days,
    -- compute mortality among admissions in the group's top quartile
    SAFE_DIVIDE(SUM(CASE WHEN gb.los_days >= g.los_q3 THEN gb.died_in_hosp ELSE 0 END), NULLIF(SUM(CASE WHEN gb.los_days >= g.los_q3 THEN 1 ELSE 0 END),0)) AS mortality_in_top_quartile
  FROM
    group_q3 g
  LEFT JOIN
    group_base gb
  ON
    (g.group_name = 'serotonergic' AND gb.serotonergic_flag = 1)
    OR
    (g.group_name = 'icu' AND gb.icu_flag = 1)
  GROUP BY
    g.group_name, g.n_adm, g.mean_los, g.mortality_rate, g.los_q3
)
-- Final outputs:
-- 1) medication complexity distribution (mean, p25/p50/p75)
-- 2) group comparison table (serotonergic vs ICU) with mean LOS, mortality, group Q3 (top-quartile LOS),
--    and mortality among that top quartile
SELECT
  'medication_complexity_distribution' AS report_section,
  STRUCT(
    mcs.n_admissions AS n_admissions,
    mcs.mean_med_count AS mean_med_count,
    CAST(mcs.med_count_quartiles[OFFSET(1)] AS INT64) AS med_count_p25,
    CAST(mcs.med_count_quartiles[OFFSET(2)] AS INT64) AS med_count_p50,
    CAST(mcs.med_count_quartiles[OFFSET(3)] AS INT64) AS med_count_p75
  ) AS med_complexity_summary,
  CAST(NULL AS STRUCT<
    group_name STRING,
    n_adm INT64,
    mean_los_days FLOAT64,
    mortality_rate_overall FLOAT64,
    los_q3_days FLOAT64,
    mortality_in_top_quartile FLOAT64
  >) AS group_comparison
FROM med_complexity_stats mcs

UNION ALL

SELECT
  'group_comparison' AS report_section,
  CAST(NULL AS STRUCT<
    n_admissions INT64,
    mean_med_count FLOAT64,
    med_count_p25 INT64,
    med_count_p50 INT64,
    med_count_p75 INT64
  >) AS med_complexity_summary,
  -- return a STRUCT of the group metrics for convenience
  STRUCT(
    gtq.group_name AS group_name,
    CAST(gtq.n_adm AS INT64) AS n_adm,
    gtq.mean_los_days,
    gtq.mortality_rate_overall,
    gtq.los_q3_days,
    ROUND(gtq.mortality_in_top_quartile,4) AS mortality_in_top_quartile
  ) AS group_comparison
FROM group_top_quartile_stats gtq
ORDER BY report_section DESC;