WITH male_icu_patients_85_95 AS (
  -- Get male patients aged 85-95
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
),

icu_stays_with_temps AS (
  -- Get ICU stays for these patients with temperature measurements
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    AVG(ce.valuenum) AS avg_temp_c
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id
    AND icu.hadm_id = ce.hadm_id
    AND icu.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    icu.subject_id IN (SELECT subject_id FROM male_icu_patients_85_95)
    AND di.label = 'Temperature C'  -- Assuming itemid for Celsius temperature
    AND ce.valuenum IS NOT NULL
  GROUP BY
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
)

-- Calculate percentile rank of 36.0°C among the average temperatures
SELECT
  PERCENT_RANK() OVER (ORDER BY avg_temp_c) AS percentile_rank,
  avg_temp_c
FROM
  icu_stays_with_temps
WHERE
  avg_temp_c IS NOT NULL
ORDER BY
  avg_temp_c;