WITH
-- Get male patients aged 74-84
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 74 AND 84
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) AS icu_los_hours,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    s.hadm_id = a.hadm_id
  JOIN
    eligible_patients p
  ON
    s.subject_id = p.subject_id
),

-- Get temperature measurements (fever > 38.5°C)
fever_hours AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    TIMESTAMP_DIFF(c.charttime, i.icu_intime, HOUR) AS hours_since_admission,
    CASE WHEN c.valuenum > 38.5 THEN 1 ELSE 0 END AS has_fever,
    NULL AS has_hypoxemia,
    NULL AS has_tachypnea
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays i
  ON
    c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  WHERE
    c.itemid IN (223761, 223762) -- Temperature itemids
    AND TIMESTAMP_DIFF(c.charttime, i.icu_intime, HOUR) BETWEEN 0 AND 48
),

-- Get SpO2 measurements (<90%)
spo2_hours AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    TIMESTAMP_DIFF(c.charttime, i.icu_intime, HOUR) AS hours_since_admission,
    NULL AS has_fever,
    CASE WHEN c.valuenum < 90 THEN 1 ELSE 0 END AS has_hypoxemia,
    NULL AS has_tachypnea
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays i
  ON
    c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  WHERE
    c.itemid IN (220277, 220210) -- SpO2 itemids
    AND TIMESTAMP_DIFF(c.charttime, i.icu_intime, HOUR) BETWEEN 0 AND 48
),

-- Get respiratory rate measurements (>20)
rr_hours AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    TIMESTAMP_DIFF(c.charttime, i.icu_intime, HOUR) AS hours_since_admission,
    NULL AS has_fever,
    NULL AS has_hypoxemia,
    CASE WHEN c.valuenum > 20 THEN 1 ELSE 0 END AS has_tachypnea
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays i
  ON
    c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  WHERE
    c.itemid IN (220210, 224689) -- Respiratory rate itemids
    AND TIMESTAMP_DIFF(c.charttime, i.icu_intime, HOUR) BETWEEN 0 AND 48
),

-- Combine all instability conditions
instability_hours AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    hours_since_admission,
    MAX(has_fever) AS has_fever,
    MAX(has_hypoxemia) AS has_hypoxemia,
    MAX(has_tachypnea) AS has_tachypnea,
    CASE WHEN MAX(has_fever) = 1 OR MAX(has_hypoxemia) = 1 OR MAX(has_tachypnea) = 1 THEN 1 ELSE 0 END AS has_instability
  FROM (
    SELECT * FROM fever_hours
    UNION ALL
    SELECT * FROM spo2_hours
    UNION ALL
    SELECT * FROM rr_hours
  )
  GROUP BY
    subject_id, hadm_id, stay_id, hours_since_admission
),

-- Calculate total instability hours per patient
patient_instability AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    COUNT(DISTINCT ih.hours_since_admission) AS instability_hours,
    SUM(ih.has_fever) AS fever_hours,
    SUM(ih.has_hypoxemia) AS hypoxemia_hours,
    SUM(ih.has_tachypnea) AS tachypnea_hours,
    s.icu_los_hours,
    s.hospital_expire_flag
  FROM
    icu_stays i
  JOIN
    instability_hours ih
  ON
    i.subject_id = ih.subject_id AND i.hadm_id = ih.hadm_id AND i.stay_id = ih.stay_id
  JOIN
    icu_stays s
  ON
    i.subject_id = s.subject_id AND i.hadm_id = s.hadm_id AND i.stay_id = s.stay_id
  GROUP BY
    i.subject_id, i.hadm_id, i.stay_id, s.icu_los_hours, s.hospital_expire_flag
),

-- Calculate 90th percentile of instability hours
percentile_90 AS (
  SELECT
    PERCENTILE_CONT(instability_hours, 0.9) OVER() AS p90_instability
  FROM
    patient_instability
  LIMIT 1
),

-- Get top decile patients
top_decile AS (
  SELECT
    pi.*,
    p.p90_instability
  FROM
    patient_instability pi
  CROSS JOIN
    percentile_90 p
  WHERE
    pi.instability_hours >= p.p90_instability
)

-- Final results
SELECT
  -- 90th percentile instability hours
  (SELECT p90_instability FROM percentile_90) AS p90_instability_hours,

  -- Top decile statistics
  COUNT(*) AS top_decile_count,
  AVG(icu_los_hours) AS mean_icu_los_hours,
  AVG(hospital_expire_flag) * 100 AS mortality_percentage,
  AVG(fever_hours) AS mean_fever_hours,
  AVG(hypoxemia_hours) AS mean_hypoxemia_hours,
  AVG(tachypnea_hours) AS mean_tachypnea_hours
FROM
  top_decile;