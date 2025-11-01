WITH diag AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE WHEN UPPER(d.long_title) LIKE '%SEPTIC SHOCK%' THEN 1 ELSE 0 END) AS has_shock,
    MAX(CASE WHEN UPPER(d.long_title) LIKE '%SEPSIS%' THEN 1 ELSE 0 END) AS has_sepsis
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY di.subject_id, di.hadm_id
),
classified AS (
  SELECT
    subject_id,
    hadm_id,
    CASE 
      WHEN has_shock = 1 THEN 'Septic shock'
      WHEN has_sepsis = 1 THEN 'Sepsis'
      ELSE NULL
    END AS condition_group
  FROM diag
  WHERE has_shock = 1 OR has_sepsis = 1
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    pat.gender,
    pat.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime,
    c.condition_group,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON a.subject_id = pat.subject_id
  JOIN classified c
    ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 53 AND 63
),
cohort2 AS (
  SELECT
    *,
    CASE WHEN los_days <= 7 THEN 'LOS_le_7' ELSE 'LOS_gt_7' END AS los_group,
    CASE WHEN hospital_expire_flag = 1 THEN DATETIME_DIFF(deathtime, admittime, DAY) END AS ttd_days
  FROM cohort
),
agg AS (
  SELECT
    condition_group,
    los_group,
    COUNT(*) AS N,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS mortality_pct,
    APPROX_QUANTILES(ttd_days, 100)[OFFSET(50)] AS median_ttd_days
  FROM cohort2
  GROUP BY condition_group, los_group
),
joined AS (
  SELECT
    le.los_group,
    le.N AS N_sepsis,
    le.mortality_pct AS mort_sepsis,
    le.median_ttd_days AS median_ttd_sepsis,
    sh.N AS N_shock,
    sh.mortality_pct AS mort_shock,
    sh.median_ttd_days AS median_ttd_shock,
    (sh.mortality_pct - le.mortality_pct) AS abs_diff_pct,
    SAFE_DIVIDE(sh.mortality_pct, le.mortality_pct) AS rel_diff_ratio
  FROM agg le
  JOIN agg sh
    ON le.los_group = sh.los_group
   AND le.condition_group = 'Sepsis'
   AND sh.condition_group = 'Septic shock'
)
SELECT *
FROM joined
ORDER BY los_group;