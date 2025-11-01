WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- at least one AMI diagnosis
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_ami
      ON a.hadm_id = d_ami.hadm_id
      AND (
        REGEXP_CONTAINS(d_ami.icd_code, r'^410')    -- ICD-9 AMI
        OR REGEXP_CONTAINS(d_ami.icd_code, r'^I21') -- ICD-10 AMI
      )
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
    -- exclude any shock diagnosis
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_shock
      WHERE d_shock.hadm_id = a.hadm_id
        AND (
          REGEXP_CONTAINS(d_shock.icd_code, r'^785\.5') -- ICD-9 shock
          OR REGEXP_CONTAINS(d_shock.icd_code, r'^R57')   -- ICD-10 shock
        )
    )
    -- exclude any respiratory failure diagnosis
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_rf
      WHERE d_rf.hadm_id = a.hadm_id
        AND (
          REGEXP_CONTAINS(d_rf.icd_code, r'^518\.81') -- ICD-9 resp failure
          OR REGEXP_CONTAINS(d_rf.icd_code, r'^518\.82')
          OR REGEXP_CONTAINS(d_rf.icd_code, r'^J96')   -- ICD-10 resp failure
        )
    )
),
comorbidities AS (
  SELECT
    c.*,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = c.hadm_id
        AND (
          REGEXP_CONTAINS(d.icd_code, r'^585')  -- ICD-9 CKD
          OR REGEXP_CONTAINS(d.icd_code, r'^N18') -- ICD-10 CKD
        )
    ) THEN 1 ELSE 0 END AS ckd_flag,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = c.hadm_id
        AND (
          REGEXP_CONTAINS(d.icd_code, r'^250')  -- ICD-9 diabetes
          OR REGEXP_CONTAINS(d.icd_code, r'^E10') -- ICD-10 Type 1 DM
          OR REGEXP_CONTAINS(d.icd_code, r'^E11') -- ICD-10 Type 2 DM
        )
    ) THEN 1 ELSE 0 END AS diab_flag
  FROM
    cohort c
),
grouped AS (
  SELECT
    CASE
      WHEN los_days <= 5 THEN '<=5 days'
      ELSE '>5 days'
    END AS los_group,
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS n_deaths,
    AVG(ckd_flag) AS ckd_prev,
    AVG(diab_flag) AS diab_prev
  FROM
    comorbidities
  GROUP BY
    los_group
),
metrics AS (
  SELECT
    los_group,
    n_admissions,
    n_deaths,
    SAFE_DIVIDE(n_deaths, n_admissions) AS mort_rate,
    ckd_prev,
    diab_prev
  FROM
    grouped
)
SELECT
  m_short.los_group AS group_short,
  m_short.n_admissions AS n_short,
  m_short.n_deaths AS deaths_short,
  m_short.mort_rate AS mort_rate_short,
  m_short.ckd_prev AS ckd_prev_short,
  m_short.diab_prev AS diab_prev_short,
  m_long.los_group AS group_long,
  m_long.n_admissions AS n_long,
  m_long.n_deaths AS deaths_long,
  m_long.mort_rate AS mort_rate_long,
  m_long.ckd_prev AS ckd_prev_long,
  m_long.diab_prev AS diab_prev_long,
  -- absolute and relative mortality differences
  SAFE_SUBTRACT(m_long.mort_rate, m_short.mort_rate) AS abs_mort_diff,
  SAFE_DIVIDE(m_long.mort_rate, m_short.mort_rate) AS rel_mort_diff
FROM
  metrics m_short
  JOIN metrics m_long
    ON m_short.los_group = '<=5 days'
   AND m_long.los_group = '>5 days';