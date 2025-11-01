WITH male_icu_patients AS (
  -- Get male ICU patients aged 37-47
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.hadm_id,
    i.stay_id,
    i.intime AS icu_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),

spo2_measurements AS (
  -- Get SpO2 measurements (itemid 220277 is SpO2)
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS spo2_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE
    c.itemid = 220277  -- SpO2 itemid
    AND d.label = 'SpO2'
),

first_spo2_per_stay AS (
  -- Get the first SpO2 measurement per ICU stay
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.spo2_value,
    ROW_NUMBER() OVER (PARTITION BY s.stay_id ORDER BY s.charttime) AS spo2_rank
  FROM
    spo2_measurements s
  JOIN
    male_icu_patients m
    ON s.subject_id = m.subject_id AND s.hadm_id = m.hadm_id
)

-- Calculate IQR of first SpO2 values
SELECT
  PERCENTILE_CONT(spo2_value, 0.25) OVER() AS q1,
  PERCENTILE_CONT(spo2_value, 0.75) OVER() AS q3,
  PERCENTILE_CONT(spo2_value, 0.75) OVER() - PERCENTILE_CONT(spo2_value, 0.25) OVER() AS iqr
FROM
  first_spo2_per_stay
WHERE
  spo2_rank = 1  -- Only the first SpO2 per stay
LIMIT 1;