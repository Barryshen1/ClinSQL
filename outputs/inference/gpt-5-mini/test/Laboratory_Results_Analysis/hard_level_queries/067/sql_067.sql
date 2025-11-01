WITH
-- female inpatients age 53-63
female_age_adms AS (
  SELECT
    a.*,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
  WHERE
    LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 53 AND 63
),

-- flag admissions that have ACS diagnosis (ICD description text match)
acs_flagged AS (
  SELECT DISTINCT
    di.hadm_id,
    1 AS is_acs
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    JOIN female_age_adms fa
      ON fa.hadm_id = di.hadm_id
  WHERE
    -- require "acute" and one of the ACS terms in the diagnosis name to capture MI / unstable angina
    LOWER(dd.long_title) LIKE '%acute%'
    AND (
      LOWER(dd.long_title) LIKE '%myocardial%'
      OR LOWER(dd.long_title) LIKE '%infarction%'
      OR LOWER(dd.long_title) LIKE '%unstable angina%'
      OR LOWER(dd.long_title) LIKE '%coronary%'
    )
),

-- base cohort: female age-matched admissions with ACS flag (0/1)
cohort AS (
  SELECT
    fa.*,
    COALESCE(af.is_acs, 0) = 1 AS is_acs
  FROM
    female_age_adms fa
    LEFT JOIN acs_flagged af USING(hadm_id)
),

-- lab events in first 72 hours for cohort admissions, annotated with category and is_critical
lab_events_72h AS (
  SELECT
    c.hadm_id,
    le.subject_id,
    le.itemid,
    dl.category AS lab_category,
    COALESCE(dl.category, dl.label) AS lab_category_label,
    le.charttime,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    le.flag,
    -- mark critical if flag text suggests critical/abnormal OR numeric outside ref range when available
    (
      (LOWER(IFNULL(le.flag, '')) LIKE '%crit%' OR LOWER(IFNULL(le.flag, '')) LIKE '%abnorm%')
      OR (
        le.valuenum IS NOT NULL
        AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR
          (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
      )
    ) AS is_critical
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON le.hadm_id = c.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
      ON le.itemid = dl.itemid
  WHERE
    -- events in the first 72 hours of the admission
    le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
),

-- instability score per admission = number of distinct lab categories with at least one critical event in 72h
instability_per_adm AS (
  SELECT
    c.*,
    COALESCE(scores.num_crit_categories, 0) AS instability_score,
    -- flag whether had any critical lab in 72h
    CASE WHEN COALESCE(scores.num_crit_categories, 0) > 0 THEN 1 ELSE 0 END AS had_any_critical_in_72h,
    -- LOS in days (as fractional days)
    SAFE_DIVIDE(TIMESTAMP_DIFF(c.dischtime, c.admittime, MINUTE), 60.0 * 24.0) AS los_days
  FROM
    cohort c
    LEFT JOIN (
      SELECT
        hadm_id,
        COUNT(DISTINCT COALESCE(lab_category, lab_category_label)) AS num_crit_categories
      FROM
        lab_events_72h
      WHERE
        is_critical
      GROUP BY
        hadm_id
    ) scores
    USING(hadm_id)
),

-- compute quartiles for ACS admissions based on instability_score
acs_with_quartile AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS instability_quartile
  FROM
    instability_per_adm
  WHERE
    is_acs
),

-- aggregate quartile-level outcomes for ACS admissions
quartile_stats AS (
  SELECT
    CAST(instability_quartile AS STRING) AS label,
    COUNT(*) AS n_admissions,
    100.0 * SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_pct,
    AVG(los_days) AS avg_los_days,
    AVG(instability_score) AS mean_instability_score
  FROM
    acs_with_quartile
  GROUP BY
    instability_quartile
  ORDER BY
    CAST(instability_quartile AS INT64)
),

-- compute group-level (ACS vs control) comparisons
group_summary AS (
  SELECT
    CASE WHEN is_acs THEN 'ACS' ELSE 'Control' END AS group_label,
    COUNT(*) AS n_admissions,
    100.0 * SAFE_DIVIDE(SUM(had_any_critical_in_72h), COUNT(*)) AS pct_with_any_critical_72h,
    AVG(instability_score) AS mean_instability_score
  FROM
    instability_per_adm
  GROUP BY
    is_acs
),

-- compute relative metrics (join rows for ACS and Control to compute ratio/difference)
comparison_stats AS (
  SELECT
    g1.group_label AS group_label,
    g1.n_admissions,
    g1.pct_with_any_critical_72h,
    g1.mean_instability_score,
    -- attach comparison numbers where group_label = 'ACS' repeated; compute ratio to control below
    g2.pct_with_any_critical_72h AS control_pct_with_any_critical_72h,
    g2.mean_instability_score AS control_mean_instability_score
  FROM
    group_summary g1
    LEFT JOIN group_summary g2
      ON g2.group_label = 'Control'
  WHERE
    g1.group_label IN ('ACS', 'Control')
  ORDER BY
    CASE g1.group_label WHEN 'ACS' THEN 1 WHEN 'Control' THEN 2 ELSE 3 END
)

-- Final output: quartile stats for ACS, then group comparison rows with simple ratios/differences
SELECT
  'Quartile' AS result_type,
  label AS subgroup,
  n_admissions,
  ROUND(mortality_pct, 2) AS mortality_pct,
  ROUND(avg_los_days, 3) AS avg_los_days,
  ROUND(mean_instability_score, 3) AS mean_instability_score,
  NULL AS pct_with_any_critical_72h,
  NULL AS control_pct_with_any_critical_72h,
  NULL AS pct_ratio_to_control,
  NULL AS mean_instability_score_control,
  NULL AS mean_instability_score_diff
FROM
  quartile_stats

UNION ALL

SELECT
  'GroupComparison' AS result_type,
  group_label AS subgroup,
  n_admissions,
  NULL AS mortality_pct,
  NULL AS avg_los_days,
  ROUND(mean_instability_score, 3) AS mean_instability_score,
  ROUND(pct_with_any_critical_72h, 3) AS pct_with_any_critical_72h,
  ROUND(control_pct_with_any_critical_72h, 3) AS control_pct_with_any_critical_72h,
  -- ratio (ACS / Control) for pct_with_any_critical_72h when applicable
  CASE
    WHEN group_label = 'ACS' AND control_pct_with_any_critical_72h > 0 THEN ROUND(pct_with_any_critical_72h / control_pct_with_any_critical_72h, 3)
    WHEN group_label = 'ACS' THEN NULL
    ELSE NULL
  END AS pct_ratio_to_control,
  -- control mean for mean_instability_score (for ACS row will show control mean)
  ROUND(control_mean_instability_score, 3) AS mean_instability_score_control,
  -- difference (ACS mean - control mean)
  CASE
    WHEN group_label = 'ACS' THEN ROUND(mean_instability_score - control_mean_instability_score, 3)
    ELSE NULL
  END AS mean_instability_score_diff
FROM
  comparison_stats
ORDER BY
  result_type DESC, subgroup;