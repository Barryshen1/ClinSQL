WITH patients_filtered AS (
  SELECT p.subject_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.anchor_age BETWEEN 78 AND 88
    AND p.gender = 'M'
),
icu_stays_filtered AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime, i.los
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN patients_filtered p ON i.subject_id = p.subject_id
),
hhs_diagnoses AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code IN ('E11.01', 'E13.01')  -- HHS codes
),
cohort AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    CASE WHEN h.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS hhs_flag
  FROM icu_stays_filtered i
  LEFT JOIN hhs_diagnoses h ON i.hadm_id = h.hadm_id
),
vital_signs_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE linksto = 'chartevents'
    AND LOWER(category) = 'vital signs'
),
vitals_48h AS (
  SELECT 
    c.subject_id,
    c.stay_id,
    c.hhs_flag,
    c.los,
    ce.itemid,
    ce.valuenum,
    di.lownormalvalue,
    di.highnormalvalue,
    CASE 
      WHEN di.lownormalvalue IS NOT NULL AND di.highnormalvalue IS NOT NULL AND (ce.valuenum < di.lownormalvalue OR ce.valuenum > di.highnormalvalue) THEN 1
      WHEN di.lownormalvalue IS NOT NULL AND di.highnormalvalue IS NULL AND ce.valuenum < di.lownormalvalue THEN 1
      WHEN di.lownormalvalue IS NULL AND di.highnormalvalue IS NOT NULL AND ce.valuenum > di.highnormalvalue THEN 1
      ELSE 0 
    END AS is_abnormal
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce 
    ON c.stay_id = ce.stay_id
    AND ce.charttime >= c.intime 
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  INNER JOIN vital_signs_items vs ON ce.itemid = vs.itemid
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.d_items di ON ce.itemid = di.itemid
),
abnormal_burden AS (
  SELECT 
    stay_id,
    hhs_flag,
    los,
    AVG(CAST(is_abnormal AS FLOAT64)) AS abnormal_vital_burden
  FROM vitals_48h
  GROUP BY stay_id, hhs_flag, los
),
mortality AS (
  SELECT 
    a.hadm_id,
    MAX(a.hospital_expire_flag) AS hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN cohort c ON a.hadm_id = c.hadm_id
  GROUP BY a.hadm_id
),
summary_stats AS (
  SELECT 
    ab.hhs_flag,
    ab.abnormal_vital_burden,
    ab.los,
    m.hospital_expire_flag
  FROM abnormal_burden ab
  INNER JOIN cohort c ON ab.stay_id = c.stay_id
  INNER JOIN mortality m ON c.hadm_id = m.hadm_id
)
SELECT
  CASE WHEN hhs_flag = 1 THEN 'HHS' ELSE 'Control' END AS group_name,
  -- Composite instability score (same as abnormal_vital_burden)
  APPROX_QUANTILES(abnormal_vital_burden, 100)[OFFSET(25)] AS instability_score_p25,
  APPROX_QUANTILES(abnormal_vital_burden, 100)[OFFSET(50)] AS instability_score_p50,
  APPROX_QUANTILES(abnormal_vital_burden, 100)[OFFSET(75)] AS instability_score_p75,
  -- Mean abnormal-vital burden (same metric)
  APPROX_QUANTILES(abnormal_vital_burden, 100)[OFFSET(25)] AS burden_p25,
  APPROX_QUANTILES(abnormal_vital_burden, 100)[OFFSET(50)] AS burden_p50,
  APPROX_QUANTILES(abnormal_vital_burden, 100)[OFFSET(75)] AS burden_p75,
  -- Mean ICU LOS
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_p25,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS los_p50,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS los_p75,
  -- Mortality rate (mean, not percentiles)
  AVG(hospital_expire_flag) AS mortality_rate
FROM summary_stats
GROUP BY hhs_flag
ORDER BY hhs_flag;