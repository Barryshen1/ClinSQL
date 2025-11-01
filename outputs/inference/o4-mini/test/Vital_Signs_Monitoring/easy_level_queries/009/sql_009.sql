WITH female_elderly_stays AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  ON
    icustays.subject_id = patients.subject_id
  WHERE
    patients.gender = 'F'
    AND patients.anchor_age BETWEEN 86 AND 96
),
temp_readings AS (
  SELECT
    fe.subject_id,
    fe.hadm_id,
    fe.stay_id,
    CASE
      WHEN ce.valueuom IN ('C', 'Cel') THEN ce.valuenum * 9.0/5.0 + 32.0
      WHEN ce.valueuom IN ('F', 'Fahrenheit') THEN ce.valuenum
      ELSE NULL
    END AS temp_f
  FROM
    female_elderly_stays AS fe
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  ON
    fe.subject_id = ce.subject_id
    AND fe.hadm_id    = ce.hadm_id
    AND fe.stay_id    = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS di
  ON
    ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%temp%'
    AND ce.charttime BETWEEN fe.intime
                       AND fe.intime + INTERVAL 24 HOUR
    AND ce.valuenum IS NOT NULL
),
percentile_calc AS (
  SELECT
    APPROX_QUANTILES(temp_f, 100)[OFFSET(75)] AS p75_temp_f
  FROM
    temp_readings
)
SELECT
  p75_temp_f
FROM
  percentile_calc;