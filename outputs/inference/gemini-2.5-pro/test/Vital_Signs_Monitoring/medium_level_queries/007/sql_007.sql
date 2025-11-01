WITH spo2_per_stay AS (
  -- First, calculate the average SpO2 for each ICU stay
  SELECT
    stay_id,
    AVG(valuenum) AS avg_spo2
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid = 220277 -- O2 saturation pulseoxymetry
    AND valuenum >= 0 AND valuenum <= 100 -- Filter for valid SpO2 values
  GROUP BY
    stay_id
),

cohort_with_spo2 AS (
  -- Second, define the cohort of female patients aged 80-90 and join with their average SpO2
  SELECT
    icu.stay_id,
    sps.avg_spo2
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN
    spo2_per_stay AS sps
    ON icu.stay_id = sps.stay_id
  WHERE
    pat.gender = 'F'
    -- Calculate age at the time of ICU admission
    AND ( (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) + pat.anchor_age ) >= 80
    AND ( (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) + pat.anchor_age ) <= 90
)

-- Finally, calculate the percentile of stays with an average SpO2 <= 88%
SELECT
  100.0 * COUNTIF(avg_spo2 <= 88) / COUNT(stay_id) AS percentile_of_88
FROM
  cohort_with_spo2;