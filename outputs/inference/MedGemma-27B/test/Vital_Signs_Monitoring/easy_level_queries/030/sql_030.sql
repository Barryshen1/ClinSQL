WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 43
    AND gender = 'F'
),
ICUStays AS (
  SELECT
    p.subject_id,
    ic.stay_id,
    ic.intime
  FROM
    PatientInfo AS p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
      ON p.subject_id = ic.subject_id
),
HeartRates AS (
  SELECT
    ic.subject_id,
    ic.stay_id,
    ic.intime,
    ce.charttime,
    ce.valuenum AS heart_rate
  FROM
    ICUStays AS ic
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON ic.subject_id = ce.subject_id
      AND ic.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220176 -- Heart Rate
)
SELECT
  MIN(hr.heart_rate) AS min_first_heart_rate
FROM
  HeartRates AS hr
WHERE
  hr.charttime = (
    SELECT
      MIN(charttime)
    FROM
      HeartRates AS hr_sub
    WHERE
      hr_sub.subject_id = hr.subject_id
      AND hr_sub.stay_id = hr.stay_id
  );