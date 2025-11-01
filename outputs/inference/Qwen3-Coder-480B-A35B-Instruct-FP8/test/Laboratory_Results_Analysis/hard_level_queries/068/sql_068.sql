WITH septic_shock_cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm ON dx.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat ON adm.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu ON adm.hadm_id = icu.hadm_id
  WHERE
    LOWER(d.long_title) LIKE '%septic shock%'
    AND pat.gender = 'F'
    AND pat.anchor_age BETWEEN 89 AND 99
),
instability_scores AS (
  SELECT
    ss.subject_id,
    ss.stay_id,
    ce.valuenum AS instability_score
  FROM
    septic_shock_cohort ss
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    ss.stay_id = ce.stay_id
    AND ce.charttime BETWEEN ss.intime AND ss.intime + INTERVAL 48 HOUR
    AND ce.itemid = 227069  -- Placeholder for instability score itemid
    AND ce.valuenum IS NOT NULL
),
instability_stats AS (
  SELECT
    APPROX_QUANTILES(instability_score, 4) AS quantiles,
    AVG(instability_score) AS mean_score,
    STDDEV(instability_score) AS stddev_score
  FROM
    instability_scores
),
abnormal_labs_septic AS (
  SELECT
    ss.subject_id,
    COUNT(le.labevent_id) AS abnormal_lab_count
  FROM
    septic_shock_cohort ss
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    ss.hadm_id = le.hadm_id
    AND le.charttime BETWEEN ss.intime AND ss.intime + INTERVAL 48 HOUR
    AND le.flag = 'abnormal'
  GROUP BY
    ss.subject_id
),
general_inpatients AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 89 AND 99
),
abnormal_labs_general AS (
  SELECT
    gi.subject_id,
    COUNT(le.labevent_id) AS abnormal_lab_count
  FROM
    general_inpatients gi
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    gi.hadm_id = le.hadm_id
    AND le.flag = 'abnormal'
  GROUP BY
    gi.subject_id
),
lab_frequency_comparison AS (
  SELECT
    'septic_shock' AS cohort,
    AVG(abnormal_lab_count) AS avg_abnormal_labs,
    STDDEV(abnormal_lab_count) AS stddev_abnormal_labs
  FROM
    abnormal_labs_septic
  UNION ALL
  SELECT
    'general_inpatients' AS cohort,
    AVG(abnormal_lab_count) AS avg_abnormal_labs,
    STDDEV(abnormal_lab_count) AS stddev_abnormal_labs
  FROM
    abnormal_labs_general
),
outcome_stats AS (
  SELECT
    AVG(los) AS mean_los,
    STDDEV(los) AS stddev_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    septic_shock_cohort
)
SELECT
  (SELECT quantiles[OFFSET(1)] FROM instability_stats) AS q1_instability,
  (SELECT quantiles[OFFSET(2)] FROM instability_stats) AS median_instability,
  (SELECT quantiles[OFFSET(3)] FROM instability_stats) AS q3_instability,
  (SELECT quantiles[OFFSET(3)] - quantiles[OFFSET(1)] FROM instability_stats) AS iqr_instability,
  lfc.cohort,
  lfc.avg_abnormal_labs,
  lfc.stddev_abnormal_labs,
  os.mean_los,
  os.stddev_los,
  os.mortality_rate
FROM
  lab_frequency_comparison lfc
CROSS JOIN
  outcome_stats os;