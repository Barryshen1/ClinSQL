WITH septic_shock_icd AS (
  -- ICD-9: 785.52, ICD-10: R6521 (stored as R65.21 in MIMIC-IV)
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('78552', 'R6521', 'R65.21')
),
admissions_with_septic_shock AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    pat.gender,
    pat.anchor_age,
    pat.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN septic_shock_icd ssi
    ON diag.icd_code = ssi.icd_code AND diag.icd_version = ssi.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 63 AND 73
),
diagnosis_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS num_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.gender,
    a.anchor_age,
    a.dod,
    d.num_diagnoses
  FROM admissions_with_septic_shock a
  JOIN diagnosis_counts d
    ON a.hadm_id = d.hadm_id
  WHERE d.num_diagnoses > 15
),
risk_scores AS (
  SELECT
    c.*,
    drg.drg_severity,
    drg.drg_mortality
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
    ON c.hadm_id = drg.hadm_id
),
mortality AS (
  SELECT
    *,
    -- 90-day mortality: died within 90 days of admittime
    CASE
      WHEN dod IS NOT NULL AND DATETIME_DIFF(dod, admittime, DAY) <= 90 THEN 1
      WHEN deathtime IS NOT NULL AND DATETIME_DIFF(deathtime, admittime, DAY) <= 90 THEN 1
      ELSE 0
    END AS died_90d,
    -- Survivor flag: not dead in hospital
    CASE
      WHEN deathtime IS NULL THEN 1 ELSE 0 END AS survivor
  FROM risk_scores
),
major_complications_icd AS (
  -- Example major complications: acute renal failure (5849, N17), respiratory failure (51881, J96), DIC (2866, D65)
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('5849', 'N17', '51881', 'J96', '2866', 'D65')
),
complications AS (
  SELECT
    diag.hadm_id,
    COUNT(DISTINCT diag.icd_code) AS num_major_complications
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN major_complications_icd comp
    ON diag.icd_code = comp.icd_code AND diag.icd_version = comp.icd_version
  GROUP BY diag.hadm_id
),
cohort_with_complications AS (
  SELECT
    m.*,
    IFNULL(c.num_major_complications, 0) AS major_complications,
    DATETIME_DIFF(m.dischtime, m.admittime, DAY) AS los_days
  FROM mortality m
  LEFT JOIN complications c
    ON m.hadm_id = c.hadm_id
),
-- General inpatient population for comparison
general_inpatients AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    pat.gender,
    pat.anchor_age,
    pat.dod,
    d.num_diagnoses,
    drg.drg_severity,
    drg.drg_mortality,
    CASE
      WHEN pat.dod IS NOT NULL AND DATETIME_DIFF(pat.dod, adm.admittime, DAY) <= 90 THEN 1
      WHEN adm.deathtime IS NOT NULL AND DATETIME_DIFF(adm.deathtime, adm.admittime, DAY) <= 90 THEN 1
      ELSE 0
    END AS died_90d,
    CASE
      WHEN adm.deathtime IS NULL THEN 1 ELSE 0 END AS survivor,
    IFNULL(c.num_major_complications, 0) AS major_complications,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN diagnosis_counts d
    ON adm.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
    ON adm.hadm_id = drg.hadm_id
  LEFT JOIN complications c
    ON adm.hadm_id = c.hadm_id
),
-- For percentile calculation: risk score and LOS for 68M, 16 diagnoses
profile AS (
  SELECT
    gi.*,
    PERCENT_RANK() OVER (ORDER BY drg_severity) AS risk_score_percentile,
    PERCENT_RANK() OVER (ORDER BY los_days) AS los_percentile
  FROM general_inpatients gi
  WHERE gi.gender = 'M'
    AND gi.anchor_age = 68
    AND gi.num_diagnoses = 16
)
SELECT
  -- Part 1: Cohort stats
  (SELECT COUNT(*) FROM cohort_with_complications) AS cohort_size,
  (SELECT ROUND(AVG(drg_severity),2) FROM cohort_with_complications WHERE drg_severity IS NOT NULL) AS mean_risk_score,
  (SELECT ROUND(AVG(died_90d),3) FROM cohort_with_complications) AS mortality_90d_rate,
  (SELECT ROUND(AVG(CASE WHEN major_complications > 0 THEN 1 ELSE 0 END),3) FROM cohort_with_complications) AS major_complication_rate,
  (SELECT ROUND(AVG(los_days),2) FROM cohort_with_complications WHERE survivor=1) AS survivor_los_mean,
  -- Part 2: General inpatient comparison
  (SELECT ROUND(AVG(CASE WHEN major_complications > 0 THEN 1 ELSE 0 END),3) FROM general_inpatients) AS general_major_complication_rate,
  (SELECT ROUND(AVG(los_days),2) FROM general_inpatients WHERE survivor=1) AS general_survivor_los_mean,
  -- Part 3: Percentile for 68M, 16 diagnoses
  (SELECT ROUND(AVG(risk_score_percentile),3) FROM profile) AS risk_score_percentile_68M_16dx,
  (SELECT ROUND(AVG(los_percentile),3) FROM profile) AS los_percentile_68M_16dx;