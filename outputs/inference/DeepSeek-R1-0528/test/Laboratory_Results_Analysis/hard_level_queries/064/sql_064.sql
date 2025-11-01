WITH
-- Acute pancreatitis cohort (female, 65-75)
pancreatitis_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 65 AND 75
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (icd_version = 9 AND icd_code = '5770') OR
        (icd_version = 10 AND icd_code LIKE 'K85%')
    )
),
-- Lab instability scores for pancreatitis cohort (first 48h)
pancreatitis_lab_instability AS (
  SELECT
    pc.hadm_id,
    -- Instability score: count of abnormal labs (any non-null flag)
    COUNT(le.flag) AS instability_score,
    -- Critical lab flag: 1 if any 'panic' flag exists, else 0
    MAX(CASE WHEN le.flag = 'panic' THEN 1 ELSE 0 END) AS has_critical_lab
  FROM pancreatitis_cohort pc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pc.hadm_id = le.hadm_id
    AND le.charttime BETWEEN pc.admittime AND DATETIME_ADD(pc.admittime, INTERVAL 48 HOUR)
    AND le.flag IS NOT NULL  -- Only count abnormal/critical labs
  GROUP BY pc.hadm_id
),
-- Combine cohort with lab scores
pancreatitis_with_scores AS (
  SELECT
    pc.*,
    COALESCE(pli.instability_score, 0) AS instability_score,
    COALESCE(pli.has_critical_lab, 0) AS has_critical_lab
  FROM pancreatitis_cohort pc
  LEFT JOIN pancreatitis_lab_instability pli
    ON pc.hadm_id = pli.hadm_id
),
-- Assign quintiles based on instability score
pancreatitis_quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY instability_score) AS quintile
  FROM pancreatitis_with_scores
),
-- Control group (female, 65-75, no pancreatitis)
control_group AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    -- Lab instability and critical flags (same logic as pancreatitis)
    COALESCE(COUNT(le.flag), 0) AS instability_score,
    COALESCE(MAX(CASE WHEN le.flag = 'panic' THEN 1 ELSE 0 END), 0) AS has_critical_lab
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON adm.hadm_id = le.hadm_id
    AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 48 HOUR)
    AND le.flag IS NOT NULL
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 65 AND 75
    AND adm.hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (icd_version = 9 AND icd_code = '5770') OR
        (icd_version = 10 AND icd_code LIKE 'K85%')
    )
  GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag
),
-- Aggregate control group metrics
control_metrics AS (
  SELECT
    AVG(instability_score) AS mean_instability_control,
    AVG(los) AS mean_los_control,
    AVG(hospital_expire_flag) * 100 AS mortality_rate_control,
    AVG(has_critical_lab) * 100 AS pct_critical_labs_control
  FROM control_group
)
-- Final output: pancreatitis quintiles vs. control
SELECT
  quintile,
  COUNT(*) AS count_patients,
  AVG(instability_score) AS mean_instability,
  AVG(los) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS mortality_rate,
  AVG(has_critical_lab) * 100 AS pct_critical_labs,
  (SELECT pct_critical_labs_control FROM control_metrics) AS control_pct_critical_labs
FROM pancreatitis_quintiles
GROUP BY quintile
ORDER BY quintile;