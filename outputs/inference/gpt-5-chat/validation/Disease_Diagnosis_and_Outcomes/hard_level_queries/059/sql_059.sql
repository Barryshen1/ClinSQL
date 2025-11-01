WITH
-- All male patients aged 59-69
base AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    d.drg_mortality
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
),
-- Diagnoses per admission
dx AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    dd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
),
-- Flag cohorts
flags AS (
  SELECT
    b.*,
    MAX(CASE WHEN LOWER(long_title) LIKE '%ketoacidosis%' THEN 1 ELSE 0 END) AS has_dka,
    MAX(CASE WHEN LOWER(long_title) LIKE '%acute kidney%' THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE WHEN LOWER(long_title) LIKE '%acute respiratory distress%' THEN 1 ELSE 0 END) AS has_ards
  FROM base b
  LEFT JOIN dx
    ON b.subject_id = dx.subject_id
    AND b.hadm_id = dx.hadm_id
  GROUP BY b.subject_id, b.hadm_id, b.anchor_age, b.gender, b.admittime, b.dischtime, b.hospital_expire_flag, b.dod, b.drg_mortality
),
-- Calculate mortality within 30 days of admission
mort_flags AS (
  SELECT
    *,
    CASE
      WHEN dod IS NOT NULL
       AND TIMESTAMP_DIFF(dod, admittime, DAY) <= 30
      THEN 1 ELSE 0
    END AS mort30
  FROM flags
),
-- Aggregate metrics for each cohort
agg AS (
  SELECT
    cohort,
    AVG(drg_mortality) AS mean_risk_score,
    AVG(mort30) AS mort30_rate,
    AVG(has_aki) AS aki_rate,
    AVG(has_ards) AS ards_rate,
    AVG(CASE WHEN hospital_expire_flag = 0 THEN TIMESTAMP_DIFF(dischtime, admittime, DAY) END) AS mean_survivor_los
  FROM (
    SELECT
      CASE WHEN has_dka = 1 THEN 'DKA' ELSE 'General' END AS cohort,
      *
    FROM mort_flags
  ) t
  GROUP BY cohort
),
-- Percentile rank of DKA mean risk among general cohort admissions
ranked AS (
  SELECT
    hadm_id,
    drg_mortality,
    PERCENT_RANK() OVER (ORDER BY drg_mortality) AS risk_percentile
  FROM mort_flags
  WHERE has_dka = 0 -- general cohort
    AND drg_mortality IS NOT NULL
),
dka_percentile AS (
  SELECT
    AVG(risk_percentile) AS dka_mean_risk_percentile
  FROM ranked
  JOIN mort_flags mf
    ON ranked.hadm_id = mf.hadm_id
  WHERE mf.has_dka = 1
)
SELECT
  a.*,
  p.dka_mean_risk_percentile
FROM agg a
LEFT JOIN dka_percentile p
  ON a.cohort = 'DKA';