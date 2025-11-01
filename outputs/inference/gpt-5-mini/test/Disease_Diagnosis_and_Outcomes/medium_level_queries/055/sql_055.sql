WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- admission must have at least one diagnosis whose long_title mentions "complication"
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
        ON di.icd_code = dic.icd_code
        AND di.icd_version = dic.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dic.long_title) LIKE '%complication%'
    )
),

-- Compute quartile boundaries for LOS (approximate quantiles)
los_quantiles AS (
  SELECT APPROX_QUANTILES(los_days, 4) AS q_arr
  FROM cohort_admissions
),

-- Enrich cohort with quartile, ICU flag and therapy flags (vent, vasopressors, RRT)
cohort_flags AS (
  SELECT
    c.*,
    -- quartile boundaries: q_arr has 5 elements: min, q1, q2, q3, max
    CASE
      WHEN c.los_days <= q.q_arr[OFFSET(1)] THEN 1
      WHEN c.los_days <= q.q_arr[OFFSET(2)] THEN 2
      WHEN c.los_days <= q.q_arr[OFFSET(3)] THEN 3
      ELSE 4
    END AS quartile_num,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE icu.hadm_id = c.hadm_id
      ) THEN 'ICU' ELSE 'Non-ICU' END AS care_setting,
    -- mechanical ventilation evidence
    CASE WHEN (
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
          ON pi.icd_code = dip.icd_code
          AND pi.icd_version = dip.icd_version
        WHERE pi.hadm_id = c.hadm_id
          AND LOWER(dip.long_title) LIKE '%ventil%'
      )
      OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
        WHERE h.hadm_id = c.hadm_id
          AND LOWER(COALESCE(h.short_description, '')) LIKE '%ventil%'
      )
      OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        WHERE pe.hadm_id = c.hadm_id
          AND (
            LOWER(COALESCE(pe.ordercategoryname, '')) LIKE '%ventil%'
            OR LOWER(COALESCE(pe.value, '')) LIKE '%ventil%'
          )
      )
    ) THEN 1 ELSE 0 END AS mechvent_flag,
    -- vasopressor evidence (search common vasopressor drug names in prescriptions/pharmacy)
    CASE WHEN (
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        WHERE pr.hadm_id = c.hadm_id
          AND (
            LOWER(COALESCE(pr.drug, '')) LIKE '%norepinephrine%'
            OR LOWER(COALESCE(pr.drug, '')) LIKE '%norepi%'
            OR LOWER(COALESCE(pr.drug, '')) LIKE '%norep%'
            OR LOWER(COALESCE(pr.drug, '')) LIKE '%epinephrine%'
            OR LOWER(COALESCE(pr.drug, '')) LIKE '%phenylephrine%'
            OR LOWER(COALESCE(pr.drug, '')) LIKE '%vasopressin%'
            OR LOWER(COALESCE(pr.drug, '')) LIKE '%dopamine%'
            OR LOWER(COALESCE(pr.drug, '')) LIKE '%dobutamine%'
          )
      )
      OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
        WHERE ph.hadm_id = c.hadm_id
          AND (
            LOWER(COALESCE(ph.medication, '')) LIKE '%norepinephrine%'
            OR LOWER(COALESCE(ph.medication, '')) LIKE '%norepi%'
            OR LOWER(COALESCE(ph.medication, '')) LIKE '%epinephrine%'
            OR LOWER(COALESCE(ph.medication, '')) LIKE '%phenylephrine%'
            OR LOWER(COALESCE(ph.medication, '')) LIKE '%vasopressin%'
            OR LOWER(COALESCE(ph.medication, '')) LIKE '%dopamine%'
            OR LOWER(COALESCE(ph.medication, '')) LIKE '%dobutamine%'
          )
      )
    ) THEN 1 ELSE 0 END AS vasopressor_flag,
    -- RRT evidence (dialysis / CRRT / hemofiltration)
    CASE WHEN (
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi2
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip2
          ON pi2.icd_code = dip2.icd_code
          AND pi2.icd_version = dip2.icd_version
        WHERE pi2.hadm_id = c.hadm_id
          AND (
            LOWER(dip2.long_title) LIKE '%dialysis%'
            OR LOWER(dip2.long_title) LIKE '%hemodialysis%'
            OR LOWER(dip2.long_title) LIKE '%hemofiltration%'
            OR LOWER(dip2.long_title) LIKE '%continuous renal replacement%'
            OR LOWER(dip2.long_title) LIKE '%crrt%'
          )
      )
      OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h2
        WHERE h2.hadm_id = c.hadm_id
          AND (
            LOWER(COALESCE(h2.short_description, '')) LIKE '%dialysis%'
            OR LOWER(COALESCE(h2.short_description, '')) LIKE '%hemodialysis%'
            OR LOWER(COALESCE(h2.short_description, '')) LIKE '%crrt%'
          )
      )
      OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe2
        WHERE pe2.hadm_id = c.hadm_id
          AND (
            LOWER(COALESCE(pe2.ordercategoryname, '')) LIKE '%dialysis%'
            OR LOWER(COALESCE(pe2.value, '')) LIKE '%dialysis%'
            OR LOWER(COALESCE(pe2.value, '')) LIKE '%crrt%'
            OR LOWER(COALESCE(pe2.value, '')) LIKE '%hemodialysis%'
          )
      )
    ) THEN 1 ELSE 0 END AS rrt_flag
  FROM cohort_admissions c
  CROSS JOIN los_quantiles q
),

-- Aggregate by care setting and quartile
agg_by_quartile AS (
  SELECT
    care_setting,
    quartile_num,
    CONCAT('Q', CAST(quartile_num AS STRING)) AS quartile_label,
    COUNT(1) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    100.0 * SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(1)) AS mortality_pct,
    100.0 * SAFE_DIVIDE(SUM(mechvent_flag), COUNT(1)) AS pct_mech_vent,
    100.0 * SAFE_DIVIDE(SUM(vasopressor_flag), COUNT(1)) AS pct_vasopressor,
    100.0 * SAFE_DIVIDE(SUM(rrt_flag), COUNT(1)) AS pct_rrt
  FROM cohort_flags
  GROUP BY care_setting, quartile_num
),

-- Extract Q1 mortality per care_setting as baseline
baseline_q1 AS (
  SELECT
    care_setting,
    mortality_pct AS q1_mortality_pct
  FROM agg_by_quartile
  WHERE quartile_num = 1
)

-- Final: join aggregated results to baseline to compute absolute and relative differences vs Q1
SELECT
  a.care_setting,
  a.quartile_label,
  a.n_admissions,
  a.deaths,
  ROUND(a.mortality_pct, 2) AS mortality_pct,
  ROUND(a.mortality_pct - COALESCE(b.q1_mortality_pct, 0), 2) AS absolute_diff_vs_Q1_pctpts,
  CASE
    WHEN b.q1_mortality_pct IS NULL OR b.q1_mortality_pct = 0 THEN NULL
    ELSE ROUND(SAFE_DIVIDE(a.mortality_pct, b.q1_mortality_pct), 2)
  END AS relative_vs_Q1,
  ROUND(a.pct_mech_vent, 2) AS pct_mechanical_ventilation,
  ROUND(a.pct_vasopressor, 2) AS pct_vasopressors,
  ROUND(a.pct_rrt, 2) AS pct_rrt
FROM agg_by_quartile a
LEFT JOIN baseline_q1 b
  ON a.care_setting = b.care_setting
ORDER BY
  a.care_setting DESC,
  a.quartile_num;