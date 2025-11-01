WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 53
    AND gender = 'F'
), ICUStays AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
      ON a.hadm_id = ic.hadm_id
    JOIN PatientInfo AS p
      ON a.subject_id = p.subject_id
  WHERE
    ic.los BETWEEN 48 AND 58
), HeartRate AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ce.charttime,
    ce.valuenum AS heart_rate
  FROM
    ICUStays AS ic
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON ic.subject_id = ce.subject_id
      AND ic.hadm_id = ce.hadm_id
      AND ic.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220177 -- Heart Rate
    AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
), AKI AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    le.charttime,
    le.valuenum AS creatinine
  FROM
    ICUStays AS ic
    JOIN `physionet-data.mimiciv_3_1_icu.labevents` AS le
      ON ic.subject_id = le.subject_id
      AND ic.hadm_id = le.hadm_id
      AND ic.stay_id = le.stay_id
  WHERE
    le.itemid = 50912 -- Creatinine
    AND le.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
), AvgHeartRate AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(heart_rate) AS avg_hr
  FROM
    HeartRate
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
), AKI_Rate AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNT(DISTINCT creatinine) AS aki_count
  FROM
    AKI
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
)
SELECT
  CASE
    WHEN avg_hr < 60
    THEN '<60'
    WHEN avg_hr BETWEEN 60 AND 99
    THEN '60-99'
    WHEN avg_hr BETWEEN 100 AND 119
    THEN '100-119'
    ELSE '>=120'
  END AS hr_category,
  COUNT(*) AS count
FROM
  AvgHeartRate
GROUP BY
  hr_category
ORDER BY
  CASE
    WHEN hr_category = '<60'
    THEN 1
    WHEN hr_category = '60-99'
    THEN 2
    WHEN hr_category = '100-119'
    THEN 3
    ELSE 4
  END;