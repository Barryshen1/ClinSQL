WITH
-- Define our target cohort: female inpatients 43-53 with heart failure and ICU stay
target_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` s ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (di.icd_code LIKE 'I50.%' OR di.icd_code LIKE '428.%') -- Heart failure ICD codes
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Calculate SAPS-II risk score (using first recorded value)
risk_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    valuenum AS sapsii_score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE ce.itemid = 223900 -- SAPS-II score
    AND di.label = 'SAPS-II'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id, stay_id ORDER BY charttime) = 1
),

-- Calculate 30-day mortality
mortality AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN hospital_expire_flag = 1 THEN 1
      WHEN DATE_DIFF(DATE(deathtime), DATE(admittime), DAY) <= 30 THEN 1
      ELSE 0
    END AS died_within_30days
  FROM target_cohort
),

-- Calculate major complications (using procedure codes for complications)
complications AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN icd_code IN (
      -- Example complication codes (would need full list)
      '997.1', '997.2', '997.3', '997.4', '997.5', '997.6', '997.7', '997.8', '997.9',
      'T81.1', 'T81.2', 'T81.3', 'T81.4', 'T81.5', 'T81.6', 'T81.7', 'T81.8', 'T81.9'
    ) THEN 1 ELSE 0 END) AS had_major_complication
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY subject_id, hadm_id
),

-- Calculate LOS for survivors
los_survivors AS (
  SELECT
    subject_id,
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24 AS los_days
  FROM target_cohort
  WHERE hospital_expire_flag = 0
),

-- Comparison group: all female patients 43-53
comparison_group AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    ce.valuenum AS sapsii_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` s ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON s.subject_id = ce.subject_id AND s.hadm_id = ce.hadm_id AND s.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND ce.itemid = 223900 -- SAPS-II score
    AND di.label = 'SAPS-II'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id, a.hadm_id ORDER BY ce.charttime) = 1
),

-- Calculate percentiles for comparison
risk_percentiles AS (
  SELECT
    sapsii_score,
    PERCENT_RANK() OVER (ORDER BY sapsii_score) AS percentile
  FROM comparison_group
)

-- Final results
SELECT
  -- Median and IQR for risk score
  APPROX_QUANTILES(rs.sapsii_score, 4)[OFFSET(1)] AS median_risk_score,
  APPROX_QUANTILES(rs.sapsii_score, 4)[OFFSET(0)] AS q1_risk_score,
  APPROX_QUANTILES(rs.sapsii_score, 4)[OFFSET(2)] AS q3_risk_score,

  -- 30-day mortality rate
  AVG(m.died_within_30days) AS mortality_30day_rate,

  -- Major complication rate
  AVG(c.had_major_complication) AS major_complication_rate,

  -- Average LOS among survivors
  AVG(ls.los_days) AS avg_los_survivors,

  -- Risk percentile vs all females 43-53
  AVG(rp.percentile) AS avg_risk_percentile

FROM target_cohort tc
LEFT JOIN risk_scores rs ON tc.subject_id = rs.subject_id AND tc.hadm_id = rs.hadm_id AND tc.stay_id = rs.stay_id
LEFT JOIN mortality m ON tc.subject_id = m.subject_id AND tc.hadm_id = m.hadm_id
LEFT JOIN complications c ON tc.subject_id = c.subject_id AND tc.hadm_id = c.hadm_id
LEFT JOIN los_survivors ls ON tc.subject_id = ls.subject_id AND tc.hadm_id = ls.hadm_id
LEFT JOIN risk_percentiles rp ON rs.sapsii_score = rp.sapsii_score;