WITH patients_female_51_61 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 51 AND 61
),

hf_admissions AS (
  -- admissions for those patients that have a heart-failure diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- compute LOS in days (integer)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- mark ICU if any icustay exists for that hadm
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.hadm_id = a.hadm_id
    ) THEN 1 ELSE 0 END AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_female_51_61 p ON p.subject_id = a.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code = dicd.icd_code
      AND d.icd_version = dicd.icd_version
    WHERE d.hadm_id = a.hadm_id
      AND LOWER(COALESCE(dicd.long_title, '')) LIKE '%heart failure%'
  )
),

-- compute comorbidity count = distinct ICDs per admission (simple proxy)
comorb_counts AS (
  SELECT
    h.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorb_count
  FROM hf_admissions h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON d.hadm_id = h.hadm_id
  GROUP BY h.hadm_id
),

-- assign tertiles (low/med/high) across the cohort by comorb_count
comorb_tertiles AS (
  SELECT
    c.hadm_id,
    c.comorb_count,
    NTILE(3) OVER (ORDER BY c.comorb_count) AS tertile
  FROM comorb_counts c
),

-- build the analytic admissions table with flags for MV / vaso / RRT
adm_flags AS (
  SELECT
    h.*,
    COALESCE(t.tertile, 1) AS comorb_tertile,
    CASE WHEN h.los_days < 8 THEN '<8' ELSE '>=8' END AS los_group,
    -- Mechanical ventilation flag: procedures ICD (join d_icd_procedures) or ICU procedureevents (d_items label)
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
        ON p.icd_code = dp.icd_code
        AND p.icd_version = dp.icd_version
      WHERE p.hadm_id = h.hadm_id
        AND (
          LOWER(COALESCE(dp.long_title, '')) LIKE '%ventilat%'
          OR LOWER(COALESCE(dp.long_title, '')) LIKE '%intubat%'
          OR LOWER(COALESCE(dp.long_title, '')) LIKE '%respirator%'
        )
    )
    OR EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON pe.itemid = di.itemid
      WHERE pe.hadm_id = h.hadm_id
        AND (
          LOWER(COALESCE(di.label, '')) LIKE '%ventilat%'
          OR LOWER(COALESCE(di.label, '')) LIKE '%intubat%'
        )
    ) THEN 1 ELSE 0 END AS mv_flag,

    -- Vaso flag: common vasopressors in prescriptions during admission
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      WHERE pr.hadm_id = h.hadm_id
        AND pr.starttime BETWEEN h.admittime AND h.dischtime
        AND (
          LOWER(COALESCE(pr.drug, '')) LIKE '%norepinephrine%'
          OR LOWER(COALESCE(pr.drug, '')) LIKE '%noradrenaline%'
          OR LOWER(COALESCE(pr.drug, '')) LIKE '%epinephrine%'
          OR LOWER(COALESCE(pr.drug, '')) LIKE '%adrenaline%'
          OR LOWER(COALESCE(pr.drug, '')) LIKE '%dopamine%'
          OR LOWER(COALESCE(pr.drug, '')) LIKE '%dobutamine%'
          OR LOWER(COALESCE(pr.drug, '')) LIKE '%phenylephrine%'
          OR LOWER(COALESCE(pr.drug, '')) LIKE '%vasopressin%'
          OR LOWER(COALESCE(pr.drug, '')) LIKE '%terlipressin%'
        )
    ) THEN 1 ELSE 0 END AS vaso_flag,

    -- RRT flag: dialysis/hemodialysis/hemofiltration via procedures (joined) or hcpcs
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp2
        ON p2.icd_code = dp2.icd_code
        AND p2.icd_version = dp2.icd_version
      WHERE p2.hadm_id = h.hadm_id
        AND (
          LOWER(COALESCE(dp2.long_title, '')) LIKE '%dialysis%'
          OR LOWER(COALESCE(dp2.long_title, '')) LIKE '%hemodialysis%'
          OR LOWER(COALESCE(dp2.long_title, '')) LIKE '%hemofiltr%'
          OR LOWER(COALESCE(dp2.long_title, '')) LIKE '%renal replacement%'
        )
    )
    OR EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
      WHERE hc.hadm_id = h.hadm_id
        AND (
          LOWER(COALESCE(hc.short_description, '')) LIKE '%dialysis%'
          OR LOWER(COALESCE(hc.short_description, '')) LIKE '%hemodialysis%'
          OR LOWER(COALESCE(hc.short_description, '')) LIKE '%hemofiltr%'
        )
    ) THEN 1 ELSE 0 END AS rrt_flag

  FROM hf_admissions h
  LEFT JOIN comorb_tertiles t ON t.hadm_id = h.hadm_id
),

-- aggregate counts and prevalences per (los_group, comorb_tertile, icu_flag)
agg_by_group AS (
  SELECT
    los_group,
    CASE comorb_tertile
      WHEN 1 THEN 'low'
      WHEN 2 THEN 'med'
      WHEN 3 THEN 'high'
      ELSE 'low' END AS comorb_group,
    icu_flag,
    COUNT(*) AS n_admissions,
    SUM(CAST(hospital_expire_flag AS INT64)) AS n_deaths,
    SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) AS mortality_rate,
    SUM(mv_flag) AS n_mv,
    SAFE_DIVIDE(SUM(mv_flag), COUNT(*)) AS mv_prev,
    SUM(vaso_flag) AS n_vaso,
    SAFE_DIVIDE(SUM(vaso_flag), COUNT(*)) AS vaso_prev,
    SUM(rrt_flag) AS n_rrt,
    SAFE_DIVIDE(SUM(rrt_flag), COUNT(*)) AS rrt_prev
  FROM adm_flags
  GROUP BY los_group, comorb_tertile, icu_flag
)

-- final: join ICU rows with No-ICU rows for same LOS & comorb group to compute differences
SELECT
  g_noicu.los_group,
  g_noicu.comorb_group,
  -- No-ICU metrics
  g_noicu.n_admissions AS n_noICU,
  g_noicu.n_deaths AS deaths_noICU,
  ROUND(100 * g_noicu.mortality_rate, 2) AS mortality_pct_noICU,
  ROUND(100 * g_noicu.mv_prev, 2) AS mv_pct_noICU,
  ROUND(100 * g_noicu.vaso_prev, 2) AS vaso_pct_noICU,
  ROUND(100 * g_noicu.rrt_prev, 2) AS rrt_pct_noICU,

  -- ICU metrics
  COALESCE(g_icu.n_admissions, 0) AS n_ICU,
  COALESCE(g_icu.n_deaths, 0) AS deaths_ICU,
  ROUND(100 * COALESCE(g_icu.mortality_rate, 0), 2) AS mortality_pct_ICU,
  ROUND(100 * COALESCE(g_icu.mv_prev, 0), 2) AS mv_pct_ICU,
  ROUND(100 * COALESCE(g_icu.vaso_prev, 0), 2) AS vaso_pct_ICU,
  ROUND(100 * COALESCE(g_icu.rrt_prev, 0), 2) AS rrt_pct_ICU,

  -- Differences (ICU - NoICU)
  ROUND(100 * (COALESCE(g_icu.mortality_rate, 0) - g_noicu.mortality_rate), 2) AS absolute_diff_mortality_pct,
  CASE
    WHEN g_noicu.mortality_rate = 0 THEN NULL
    ELSE ROUND(COALESCE(g_icu.mortality_rate, 0) / g_noicu.mortality_rate, 2)
  END AS relative_diff_mortality_ratio

FROM
  -- base is rows for non-ICU (icu_flag = 0) so every LOS/comorb_group is present
  (SELECT * FROM agg_by_group WHERE icu_flag = 0) g_noicu
LEFT JOIN
  (SELECT * FROM agg_by_group WHERE icu_flag = 1) g_icu
ON g_icu.los_group = g_noicu.los_group
  AND g_icu.comorb_group = g_noicu.comorb_group
ORDER BY
  -- order by LOS and comorbidity severity
  CASE los_group WHEN '<8' THEN 1 ELSE 2 END,
  CASE comorb_group WHEN 'low' THEN 1 WHEN 'med' THEN 2 WHEN 'high' THEN 3 END;