WITH cohort AS (
  -- Select male inpatients age 46-56 with AMI
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age AS age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 46 AND 56
    AND (
      -- AMI ICD-10: I21.x, I22.x; ICD-9: 410.x
      (dx.icd_version = 10 AND (dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I22%'))
      OR
      (dx.icd_version = 9 AND dx.icd_code LIKE '410%')
    )
),
complications AS (
  -- For each hadm_id, count major complications
  SELECT
    adm.hadm_id,
    COUNT(DISTINCT CASE
      -- Cardiogenic shock
      WHEN (dx.icd_version = 10 AND dx.icd_code = 'R570') OR (dx.icd_version = 9 AND dx.icd_code = '78551') THEN 'cardiogenic_shock'
      -- Acute renal failure
      WHEN (dx.icd_version = 10 AND dx.icd_code LIKE 'N17%') OR (dx.icd_version = 9 AND dx.icd_code LIKE '584%') THEN 'acute_renal_failure'
      -- Cardiac arrest
      WHEN (dx.icd_version = 10 AND dx.icd_code LIKE 'I46%') OR (dx.icd_version = 9 AND dx.icd_code = '4275') THEN 'cardiac_arrest'
      -- Stroke
      WHEN (dx.icd_version = 10 AND (dx.icd_code LIKE 'I63%' OR dx.icd_code LIKE 'I61%')) OR (dx.icd_version = 9 AND (dx.icd_code LIKE '434%' OR dx.icd_code LIKE '431%')) THEN 'stroke'
      -- Sepsis
      WHEN (dx.icd_version = 10 AND dx.icd_code LIKE 'A41%') OR (dx.icd_version = 9 AND (dx.icd_code IN ('99591','99592') OR dx.icd_code LIKE '038%')) THEN 'sepsis'
      ELSE NULL
    END) AS n_major_complications
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    adm.hadm_id IN (SELECT hadm_id FROM cohort)
  GROUP BY
    adm.hadm_id
),
cohort_with_comp AS (
  -- Merge cohort and complications, compute composite risk score
  SELECT
    c.subject_id,
    c.hadm_id,
    c.age,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.los,
    IFNULL(comp.n_major_complications, 0) AS n_major_complications,
    c.age + IFNULL(comp.n_major_complications, 0) AS composite_risk_score
  FROM
    cohort c
  LEFT JOIN
    complications comp
    ON c.hadm_id = comp.hadm_id
),
quintiles AS (
  -- Assign quintile based on composite risk score
  SELECT
    *,
    NTILE(5) OVER (ORDER BY composite_risk_score) AS risk_quintile
  FROM
    cohort_with_comp
),
agg AS (
  -- Aggregate outcomes per quintile
  SELECT
    risk_quintile,
    COUNT(*) AS n_admissions,
    100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality_pct,
    100.0 * SUM(CASE WHEN n_major_complications > 0 THEN 1 ELSE 0 END) / COUNT(*) AS major_complication_pct,
    APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_survivor_los
  FROM
    quintiles
  WHERE
    hospital_expire_flag = 0 -- For median LOS, only survivors
  GROUP BY
    risk_quintile
)
SELECT
  risk_quintile,
  n_admissions,
  ROUND(in_hospital_mortality_pct, 1) AS in_hospital_mortality_pct,
  ROUND(major_complication_pct, 1) AS major_complication_pct,
  ROUND(median_survivor_los, 1) AS median_survivor_los
FROM
  agg
ORDER BY
  risk_quintile;