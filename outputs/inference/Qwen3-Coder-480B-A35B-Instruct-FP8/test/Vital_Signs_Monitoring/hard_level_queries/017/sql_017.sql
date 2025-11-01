WITH cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    adm.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 83 AND 93
),

asthma_patients AS (
  SELECT DISTINCT
    dia.subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd dia
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON dia.icd_code = d.icd_code AND dia.icd_version = d.icd_version
  WHERE
    REGEXP_CONTAINS(d.icd_code, r'^493|J45')
),

asthma_cohort AS (
  SELECT c.*
  FROM cohort c
  JOIN asthma_patients ap
    ON c.subject_id = ap.subject_id
),

-- Define instability score logic
instability_events AS (
  SELECT
    ch.stay_id,
    CASE
      WHEN di.label IN ('Heart Rate') AND (ch.valuenum < 50 OR ch.valuenum > 130) THEN 1
      WHEN di.label IN ('SBP') AND (ch.valuenum < 90 OR ch.valuenum > 180) THEN 1
      WHEN di.label IN ('Respiratory Rate') AND (ch.valuenum < 8 OR ch.valuenum > 30) THEN 1
      WHEN di.label IN ('Temperature Celsius') AND (ch.valuenum < 35 OR ch.valuenum > 38.5) THEN 1
      WHEN di.label IN ('SpO2') AND ch.valuenum < 90 THEN 1
      ELSE 0
    END AS unstable_flag
  FROM
    physionet-data.mimiciv_3_1_icu.chartevents ch
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ch.itemid = di.itemid
  JOIN
    asthma_cohort ac
    ON ch.stay_id = ac.stay_id
  WHERE
    di.label IN ('Heart Rate', 'SBP', 'Respiratory Rate', 'Temperature Celsius', 'SpO2')
    AND ch.charttime BETWEEN ac.intime AND DATETIME_ADD(ac.intime, INTERVAL 72 HOUR)
    AND ch.valuenum IS NOT NULL
),

instability_scores AS (
  SELECT
    stay_id,
    SUM(unstable_flag) AS instability_score
  FROM
    instability_events
  GROUP BY
    stay_id
),

asthma_stats AS (
  SELECT
    STDDEV(instability_score) AS sd_instability,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95,
    AVG(icu_los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    asthma_cohort ac
  LEFT JOIN
    instability_scores iss
    ON ac.stay_id = iss.stay_id
),

-- Age-matched control cohort
control_cohort AS (
  SELECT c.*
  FROM cohort c
  LEFT JOIN asthma_patients ap
    ON c.subject_id = ap.subject_id
  WHERE ap.subject_id IS NULL
),

control_instability_events AS (
  SELECT
    ch.stay_id,
    CASE
      WHEN di.label IN ('Heart Rate') AND (ch.valuenum < 50 OR ch.valuenum > 130) THEN 1
      WHEN di.label IN ('SBP') AND (ch.valuenum < 90 OR ch.valuenum > 180) THEN 1
      WHEN di.label IN ('Respiratory Rate') AND (ch.valuenum < 8 OR ch.valuenum > 30) THEN 1
      WHEN di.label IN ('Temperature Celsius') AND (ch.valuenum < 35 OR ch.valuenum > 38.5) THEN 1
      WHEN di.label IN ('SpO2') AND ch.valuenum < 90 THEN 1
      ELSE 0
    END AS unstable_flag
  FROM
    physionet-data.mimiciv_3_1_icu.chartevents ch
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ch.itemid = di.itemid
  JOIN
    control_cohort cc
    ON ch.stay_id = cc.stay_id
  WHERE
    di.label IN ('Heart Rate', 'SBP', 'Respiratory Rate', 'Temperature Celsius', 'SpO2')
    AND ch.charttime BETWEEN cc.intime AND DATETIME_ADD(cc.intime, INTERVAL 72 HOUR)
    AND ch.valuenum IS NOT NULL
),

control_instability_scores AS (
  SELECT
    stay_id,
    SUM(unstable_flag) AS instability_score
  FROM
    control_instability_events
  GROUP BY
    stay_id
),

control_stats AS (
  SELECT
    STDDEV(instability_score) AS sd_instability,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95,
    AVG(icu_los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    control_cohort cc
  LEFT JOIN
    control_instability_scores iss
    ON cc.stay_id = iss.stay_id
)

SELECT
  'Asthma Cohort' AS cohort,
  sd_instability,
  p25,
  median,
  p75,
  p95,
  avg_icu_los,
  mortality_rate
FROM asthma_stats

UNION ALL

SELECT
  'Control Cohort' AS cohort,
  sd_instability,
  p25,
  median,
  p75,
  p95,
  avg_icu_los,
  mortality_rate
FROM control_stats;