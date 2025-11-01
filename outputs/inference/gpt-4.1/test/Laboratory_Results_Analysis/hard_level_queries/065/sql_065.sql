WITH lower_gi_bleed_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.deathtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 65 AND 75
    AND (
      diag.icd_code LIKE 'K55%' OR
      diag.icd_code LIKE 'K57%' OR
      diag.icd_code LIKE 'K62%' OR
      diag.icd_code LIKE 'K92%'
    )
),

-- Lab instability score for cohort: count abnormal labs in first 72h
cohort_lab_instability AS (
  SELECT
    lgb.subject_id,
    lgb.hadm_id,
    COUNTIF(
      lab.flag = 'abnormal'
      AND TIMESTAMP_DIFF(lab.charttime, lgb.admittime, HOUR) BETWEEN 0 AND 72
    ) AS lab_instability_score
  FROM lower_gi_bleed_admissions lgb
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON lgb.hadm_id = lab.hadm_id
  GROUP BY lgb.subject_id, lgb.hadm_id
),

-- LOS and mortality for cohort
cohort_los_mortality AS (
  SELECT
    lgb.subject_id,
    lgb.hadm_id,
    TIMESTAMP_DIFF(lgb.dischtime, lgb.admittime, HOUR)/24.0 AS los_days,
    IF(lgb.hospital_expire_flag = 1 OR lgb.deathtime IS NOT NULL, 1, 0) AS mortality
  FROM lower_gi_bleed_admissions lgb
),

-- General inpatient lab instability score (all admissions, all ages/genders)
general_lab_instability AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    COUNTIF(
      lab.flag = 'abnormal'
      AND TIMESTAMP_DIFF(lab.charttime, adm.admittime, HOUR) BETWEEN 0 AND 72
    ) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON adm.hadm_id = lab.hadm_id
  GROUP BY adm.subject_id, adm.hadm_id
)

-- Final output: 25th percentile, comparison, LOS, mortality
SELECT
  -- Cohort stats
  (SELECT APPROX_QUANTILES(lab_instability_score, 4)[OFFSET(1)] FROM cohort_lab_instability) AS cohort_lab_instability_25th_percentile,
  AVG(cli.lab_instability_score) AS cohort_lab_instability_mean,
  (SELECT APPROX_QUANTILES(lab_instability_score, 2)[OFFSET(1)] FROM cohort_lab_instability) AS cohort_lab_instability_median,
  AVG(clm.los_days) AS cohort_los_mean,
  (SELECT APPROX_QUANTILES(los_days, 2)[OFFSET(1)] FROM cohort_los_mortality) AS cohort_los_median,
  SUM(clm.mortality)/COUNT(*) AS cohort_mortality_rate,

  -- General inpatient stats
  (SELECT APPROX_QUANTILES(lab_instability_score, 4)[OFFSET(1)] FROM general_lab_instability) AS general_lab_instability_25th_percentile,
  (SELECT AVG(lab_instability_score) FROM general_lab_instability) AS general_lab_instability_mean,
  (SELECT APPROX_QUANTILES(lab_instability_score, 2)[OFFSET(1)] FROM general_lab_instability) AS general_lab_instability_median

FROM cohort_lab_instability cli
LEFT JOIN cohort_los_mortality clm
  ON cli.subject_id = clm.subject_id AND cli.hadm_id = clm.hadm_id;