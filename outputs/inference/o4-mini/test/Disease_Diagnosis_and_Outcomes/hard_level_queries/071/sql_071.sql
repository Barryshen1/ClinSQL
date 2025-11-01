WITH
-- 1. Female AMI patients age 68-78 with an ICU stay
ami_icu AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    -- Placeholder for actual risk score; replace with your scoring subquery or table join
    SAFE_CAST(NULL AS FLOAT64) AS risk_score,
    CASE
      WHEN (COALESCE(a.deathtime, p.dod) IS NOT NULL
            AND DATE_DIFF(DATE(COALESCE(a.deathtime, p.dod)), DATE(a.admittime), DAY) <= 90)
      THEN 1 ELSE 0 END AS died_within_90d
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
         AND d.icd_version = dd.icd_version
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON a.subject_id = icu.subject_id
         AND a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND (dd.icd_code LIKE '410%' OR LOWER(dd.long_title) LIKE '%acute myocardial%')
),
-- 2. Major complications in AMI ICU cohort
ami_comp AS (
  SELECT
    a.*,
    MAX(CASE WHEN dd.icd_code IN ('99591','99592','51882') OR LOWER(dd.long_title) LIKE '%septic%' THEN 1 ELSE 0 END) 
      OVER (PARTITION BY a.hadm_id) AS has_major_complication,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM
    ami_icu a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
         AND d.icd_version = dd.icd_version
),
-- 3. General female inpatients age 68-78
gen_ip AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    CASE
      WHEN (COALESCE(a.deathtime, p.dod) IS NOT NULL
            AND DATE_DIFF(DATE(COALESCE(a.deathtime, p.dod)), DATE(a.admittime), DAY) <= 90)
      THEN 1 ELSE 0 END AS died_within_90d
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),
-- 4. Major complications & LOS in general cohort
gen_comp AS (
  SELECT
    g.*,
    MAX(CASE WHEN dd.icd_code IN ('99591','99592','51882') OR LOWER(dd.long_title) LIKE '%septic%' THEN 1 ELSE 0 END)
      OVER (PARTITION BY g.hadm_id) AS has_major_complication,
    DATE_DIFF(DATE(g.dischtime), DATE(g.admittime), DAY) AS los_days
  FROM
    gen_ip g
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON g.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
         AND d.icd_version = dd.icd_version
),
-- 5. AMI ICU aggregated statistics
ami_stats AS (
  SELECT
    COUNT(*) AS n_ami,
    -- Risk score quartiles: [0]=min, [1]=Q1, [2]=median, [3]=Q3, [4]=max
    APPROX_QUANTILES(risk_score, 4) AS risk_quants,
    SUM(died_within_90d) * 1.0 / COUNT(*) AS mort_90d,
    SUM(CASE WHEN has_major_complication=1 THEN 1 ELSE 0 END)*1.0/COUNT(*) AS comp_rate,
    -- Survivor LOS median
    APPROX_QUANTILES(IF(died_within_90d=0, los_days, NULL), 2)[OFFSET(1)] AS los_med_surv
  FROM
    ami_comp
),
-- 6. General cohort aggregated statistics
gen_stats AS (
  SELECT
    COUNT(*) AS n_gen,
    SUM(has_major_complication) * 1.0 / COUNT(*) AS comp_rate,
    APPROX_QUANTILES(IF(died_within_90d=0, los_days, NULL), 2)[OFFSET(1)] AS los_med_surv
  FROM
    gen_comp
),
-- 7. Risk score percentile within AMI ICU cohort
risk_percentiles AS (
  SELECT
    subject_id,
    hadm_id,
    risk_score,
    PERCENT_RANK() OVER (ORDER BY risk_score) AS percentile_in_gen
  FROM
    ami_icu
)
SELECT
  -- AMI ICU results
  s.n_ami,
  s.risk_quants[OFFSET(2)] AS risk_median,
  s.risk_quants[OFFSET(1)] AS risk_q1,
  s.risk_quants[OFFSET(3)] AS risk_q3,
  s.mort_90d,
  s.comp_rate AS ami_comp_rate,
  s.los_med_surv AS ami_los_med_surv,
  -- General inpatient results
  g.comp_rate AS gen_comp_rate,
  g.los_med_surv AS gen_los_med_surv,
  -- Median risk percentile among AMI ICU patients
  rp.median_risk_percentile
FROM
  ami_stats s
  CROSS JOIN gen_stats g
  CROSS JOIN (
    SELECT APPROX_QUANTILES(percentile_in_gen, 2)[OFFSET(1)] AS median_risk_percentile
    FROM risk_percentiles
    WHERE risk_score IS NOT NULL
  ) rp;