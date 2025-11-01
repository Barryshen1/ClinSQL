WITH PatientDemographics AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
),
ICUStays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
),
SpO2Measurements AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.value AS spo2_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  WHERE
    c.itemid = 5061 -- SpO2 itemid
),
First24hSpO2 AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    spo2.charttime,
    spo2.spo2_value
  FROM
    ICUStays AS s
  JOIN
    SpO2Measurements AS spo2
    ON s.subject_id = spo2.subject_id
    AND s.hadm_id = spo2.hadm_id
    AND s.stay_id = spo2.stay_id
  WHERE
    spo2.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
),
SpO2Categories AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    CASE
      WHEN spo2_value < 90 THEN '<90'
      WHEN spo2_value >= 90 AND spo2_value <= 92 THEN '90-92'
      WHEN spo2_value >= 93 AND spo2_value <= 95 THEN '93-95'
      ELSE '>95'
    END AS spo2_category
  FROM
    First24hSpO2
),
AKI_Definition AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    -- AKI definition based on KDIGO criteria (need to implement this logic)
    -- This is a placeholder, the actual AKI definition needs to be implemented
    -- using lab values (creatinine) over time.
    0 AS aki_flag
  FROM
    ICUStays
),
PatientAKI AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    aki.aki_flag
  FROM
    ICUStays AS s
  JOIN
    AKI_Definition AS aki
    ON s.subject_id = aki.subject_id
    AND s.hadm_id = aki.hadm_id
    AND s.stay_id = aki.stay_id
)
SELECT
  spo2_category,
  COUNT(DISTINCT subject_id) AS N,
  AVG(spo2_value) AS mean,
  MEDIAN(spo2_value) AS median,
  PERCENTILE_CONT(0.25, spo2_value) AS IQR_25,
  PERCENTILE_CONT(0.75, spo2_value) AS IQR_75,
  AVG(aki_flag) AS aki_rate
FROM
  SpO2Categories AS spo2
JOIN
  PatientAKI AS aki
  ON spo2.subject_id = aki.subject_id
  AND spo2.hadm_id = aki.hadm_id
  AND spo2.stay_id = aki.stay_id
WHERE
  spo2.subject_id IN (
    SELECT
      p.subject_id
    FROM
      PatientDemographics AS p
    WHERE
      p.gender = 'F'
      AND p.age BETWEEN 90 AND 100
  )
GROUP BY
  spo2_category
ORDER BY
  spo2_category;