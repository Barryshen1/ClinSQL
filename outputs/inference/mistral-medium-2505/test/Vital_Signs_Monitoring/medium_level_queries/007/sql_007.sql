WITH
-- Get female patients aged 80-90 at ICU admission
female_patients_80_90 AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM i.intime) AS icu_admission_year,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icu_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    p.subject_id = i.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 80 AND 90
),

-- Get SpO2 measurements for these patients (using known SpO2 itemid 220277)
spo2_measurements AS (
  SELECT
    i.stay_id,
    ce.valuenum AS spo2_value
  FROM
    female_patients_80_90 fp
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    fp.subject_id = i.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    i.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220277  -- Known itemid for SpO2
    AND ce.valuenum BETWEEN 0 AND 100  -- Plausible SpO2 range
),

-- Calculate average SpO2 per ICU stay
avg_spo2_per_stay AS (
  SELECT
    stay_id,
    AVG(spo2_value) AS avg_spo2
  FROM
    spo2_measurements
  GROUP BY
    stay_id
  HAVING
    COUNT(spo2_value) > 0  -- Ensure at least one valid measurement
)

-- Calculate the percentile of an average SpO2 of 88%
SELECT
  CASE
    WHEN COUNT(*) = 0 THEN NULL
    ELSE COUNT(CASE WHEN avg_spo2 <= 88 THEN 1 END) * 100.0 / COUNT(*)
  END AS percentile,
  COUNT(*) AS total_stays_with_spo2
FROM
  avg_spo2_per_stay;