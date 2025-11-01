WITH temp_readings AS (
  SELECT
    icustays.stay_id,
    icustays.subject_id,
    icustays.intime,
    c.valuenum AS temp_c
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
      ON icustays.subject_id = patients.subject_id
    -- Filter to male patients aged 67–77
    AND patients.gender = 'M'
    AND patients.anchor_age BETWEEN 67 AND 77
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
      ON icustays.subject_id = c.subject_id
     AND icustays.hadm_id    = c.hadm_id
     AND icustays.stay_id    = c.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS d
      ON c.itemid = d.itemid
  WHERE
    -- Restrict to the first 24 hours of the ICU stay
    c.charttime BETWEEN icustays.intime 
                    AND TIMESTAMP_ADD(icustays.intime, INTERVAL 24 HOUR)
    -- Identify temperature measurements
    AND d.category = 'Vital Signs'
    AND LOWER(d.label) LIKE '%temp%'
    -- Ensure numeric temperature
    AND c.valuenum IS NOT NULL
),

per_stay_avg AS (
  SELECT
    stay_id,
    AVG(temp_c) AS avg_temp
  FROM temp_readings
  GROUP BY stay_id
)

SELECT
  100.0 * SUM(CASE WHEN avg_temp <= 36.0 THEN 1 ELSE 0 END) / COUNT(*) 
    AS percentile_of_36C
FROM per_stay_avg;