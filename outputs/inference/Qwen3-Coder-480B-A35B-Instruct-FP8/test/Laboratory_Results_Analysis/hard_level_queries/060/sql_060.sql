WITH cardiac_arrest_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    i.los AS icu_los,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hosp_los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.anchor_age BETWEEN 52 AND 62
    AND p.gender = 'F'
    AND (
      (d.icd_version = 9 AND d.icd_code = '4275')
      OR
      (d.icd_version = 10 AND d.icd_code = 'I469')
    )
),

control_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    i.los AS icu_los,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hosp_los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  WHERE
    p.anchor_age BETWEEN 52 AND 62
    AND p.gender = 'F'
    AND a.hadm_id NOT IN (
      SELECT hadm_id FROM cardiac_arrest_cohort
    )
),

instability_events AS (
  SELECT
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    CASE WHEN di.label = 'Heart Rate' AND (ce.valuenum < 50 OR ce.valuenum > 130) THEN 1 ELSE 0 END AS hr_abn,
    CASE WHEN di.label = 'MAP' AND (ce.valuenum < 60 OR ce.valuenum > 110) THEN 1 ELSE 0 END AS map_abn,
    CASE WHEN di.label = 'Temperature Celsius' AND (ce.valuenum < 35 OR ce.valuenum > 38.5) THEN 1 ELSE 0 END AS temp_abn,
    CASE WHEN di.label = 'Respiratory Rate' AND (ce.valuenum < 10 OR ce.valuenum > 25) THEN 1 ELSE 0 END AS rr_abn,
    CASE WHEN di.label = 'Lactate' AND ce.valuenum > 2.0 THEN 1 ELSE 0 END AS lactate_abn,
    CASE WHEN di.label = 'pH' AND (ce.valuenum < 7.32 OR ce.valuenum > 7.48) THEN 1 ELSE 0 END AS ph_abn
  FROM
    cardiac_arrest_cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    c.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    ce.charttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 48 HOUR)
    AND di.label IN ('Heart Rate', 'MAP', 'Temperature Celsius', 'Respiratory Rate', 'Lactate', 'pH')
    AND ce.valuenum IS NOT NULL
),

instability_score AS (
  SELECT
    stay_id,
    SUM(hr_abn + map_abn + temp_abn + rr_abn + lactate_abn + ph_abn) AS instability_score
  FROM
    instability_events
  GROUP BY
    stay_id
),

cardiac_summary AS (
  SELECT
    'Post-cardiac arrest' AS cohort,
    APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(instability_score, 2)[OFFSET(1)] AS median,
    AVG(hosp_los_days) AS mean_hosp_los,
    AVG(icu_los) AS mean_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    cardiac_arrest_cohort c
  LEFT JOIN
    instability_score i
  ON
    c.stay_id = i.stay_id
),

control_summary AS (
  SELECT
    'General inpatient' AS cohort,
    NULL AS q1,
    NULL AS median,
    AVG(hosp_los_days) AS mean_hosp_los,
    AVG(icu_los) AS mean_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    control_cohort
)

SELECT * FROM cardiac_summary
UNION ALL
SELECT * FROM control_summary
ORDER BY cohort;