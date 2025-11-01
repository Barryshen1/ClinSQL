WITH
-- Define ICU careunits
icu_units AS (
  SELECT DISTINCT first_careunit AS careunit
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Identify the pneumonia cohort
pneumonia_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id = d.hadm_id
   AND d.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND LOWER(dicd.long_title) LIKE '%pneumonia%'
),

-- Compute 72-hour lab instability scores for each hadm_id
instability_scores AS (
  SELECT
    le.hadm_id,
    COUNT(*) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN pneumonia_cohort pc
    ON le.hadm_id = pc.hadm_id
  WHERE
    le.charttime BETWEEN pc.admittime
                      AND TIMESTAMP_ADD(pc.admittime, INTERVAL 72 HOUR)
    AND LOWER(le.flag) IN ('abnormal','h','l')
  GROUP BY le.hadm_id
),

-- Compute critical-event frequency (ICU transfers) per admission
crit_events_cohort AS (
  SELECT
    t.hadm_id,
    COUNT(*) AS crit_event_count
  FROM `physionet-data.mimiciv_3_1_hosp.transfers` t
  JOIN pneumonia_cohort pc
    ON t.hadm_id = pc.hadm_id
  JOIN icu_units iu
    ON t.careunit = iu.careunit
  WHERE t.eventtype = 'transfer'
    AND t.intime BETWEEN pc.admittime
                    AND pc.dischtime
  GROUP BY t.hadm_id
),

-- Combine cohort metrics
cohort_metrics AS (
  SELECT
    pc.hadm_id,
    COALESCE(iscore.instability_score, 0) AS instability_score,
    COALESCE(cec.crit_event_count, 0)   AS crit_event_count,
    pc.los,
    pc.hospital_expire_flag
  FROM pneumonia_cohort pc
  LEFT JOIN instability_scores iscore
    ON pc.hadm_id = iscore.hadm_id
  LEFT JOIN crit_events_cohort cec
    ON pc.hadm_id = cec.hadm_id
),

-- Define the comparison group: all male inpatients aged 60-70
comparison_group AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
),

-- Compute critical-event frequency for the comparison group
crit_events_comparison AS (
  SELECT
    t.hadm_id,
    COUNT(*) AS crit_event_count
  FROM `physionet-data.mimiciv_3_1_hosp.transfers` t
  JOIN comparison_group cg
    ON t.hadm_id = cg.hadm_id
  JOIN icu_units iu
    ON t.careunit = iu.careunit
  WHERE t.eventtype = 'transfer'
  GROUP BY t.hadm_id
)

-- Final aggregation and reporting
SELECT
  -- 75th percentile of the cohort's 72-h lab instability score
  APPROX_QUANTILES(cm.instability_score, 100)[OFFSET(75)] AS instability_75th_pct,
  -- Mean critical-event frequency: cohort vs comparison
  AVG(cm.crit_event_count) AS cohort_mean_crit_events,
  (SELECT AVG(crit_event_count) FROM crit_events_comparison) AS all_inpatients_mean_crit_events,
  -- Cohort LOS and mortality
  AVG(cm.los) AS cohort_mean_los,
  AVG(cm.hospital_expire_flag) AS cohort_mortality_rate
FROM cohort_metrics cm;