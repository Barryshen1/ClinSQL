WITH ards_male_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays icu ON a.hadm_id = icu.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND dd.icd_code = 'J80'
    AND d.icd_version = 10
),

-- Define instability score: count of abnormal vitals/GCS in first 72h
instability_scores AS (
  SELECT
    ards.subject_id,
    ards.stay_id,
    COUNT(*) AS instability_score
  FROM
    ards_male_patients ards
  JOIN
    physionet-data.mimiciv_3_1_icu.chartevents ce ON ards.stay_id = ce.stay_id
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di ON ce.itemid = di.itemid
  WHERE
    ce.charttime BETWEEN ards.intime AND DATETIME_ADD(ards.intime, INTERVAL 72 HOUR)
    AND (
      (di.label IN ('Heart Rate', 'Respiratory Rate') AND (ce.valuenum < 40 OR ce.valuenum > 130))
      OR (di.label = 'SBP' AND (ce.valuenum < 90 OR ce.valuenum > 180))
      OR (di.label = 'Temperature C' AND (ce.valuenum < 35 OR ce.valuenum > 39))
      OR (di.label = 'GCS Total' AND ce.valuenum < 12)
    )
  GROUP BY
    ards.subject_id, ards.stay_id
),

-- Get 90th percentile of instability score
instability_threshold AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS threshold_90
  FROM
    instability_scores
),

-- Patients at or above 90th percentile
high_instability_patients AS (
  SELECT
    i.subject_id,
    i.stay_id,
    i.instability_score,
    a.hospital_expire_flag,
    a.los,
    a.hadm_id,
    a.intime
  FROM
    instability_scores i
  JOIN
    ards_male_patients a ON i.stay_id = a.stay_id
  CROSS JOIN
    instability_threshold t
  WHERE
    i.instability_score >= t.threshold_90
),

-- Mortality and mean LOS for high instability group
mortality_los AS (
  SELECT
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(los) AS mean_los
  FROM
    high_instability_patients
),

-- Critical labs for high instability group
critical_labs_high AS (
  SELECT
    COUNT(CASE WHEN l.valuenum > 2 THEN 1 END) * 1.0 / COUNT(*) AS critical_lab_rate
  FROM
    high_instability_patients h
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents l ON h.hadm_id = l.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d ON l.itemid = d.itemid
  WHERE
    l.charttime BETWEEN h.intime AND DATETIME_ADD(h.intime, INTERVAL 72 HOUR)
    AND d.label IN ('Lactate', 'Bilirubin', 'Creatinine')
),

-- General inpatients (same age/gender)
general_inpatients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays icu ON a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
),

-- Critical labs for general inpatients
critical_labs_general AS (
  SELECT
    COUNT(CASE WHEN l.valuenum > 2 THEN 1 END) * 1.0 / COUNT(*) AS critical_lab_rate_general
  FROM
    general_inpatients g
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents l ON g.hadm_id = l.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d ON l.itemid = d.itemid
  WHERE
    l.charttime BETWEEN g.intime AND DATETIME_ADD(g.intime, INTERVAL 72 HOUR)
    AND d.label IN ('Lactate', 'Bilirubin', 'Creatinine')
)

-- Final output
SELECT
  m.mortality_rate,
  m.mean_los,
  c1.critical_lab_rate AS critical_lab_rate_high_instability,
  c2.critical_lab_rate_general
FROM
  mortality_los m,
  critical_labs_high c1,
  critical_labs_general c2;