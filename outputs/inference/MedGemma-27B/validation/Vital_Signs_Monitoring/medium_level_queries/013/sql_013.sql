WITH PatientDemographics AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
), ICUStays AS (
  SELECT
    ic.subject_id,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
), SpO2Measurements AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS spo2_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  WHERE
    ce.itemid = 4070 -- SpO2 itemid
), First48HoursSpO2 AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.spo2_value,
    s.charttime
  FROM
    SpO2Measurements AS s
  INNER JOIN
    ICUStays AS ic
    ON s.subject_id = ic.subject_id AND s.stay_id = ic.stay_id
  WHERE
    s.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
), AvgSpO2PerStay AS (
  SELECT
    stay_id,
    AVG(spo2_value) AS avg_spo2
  FROM
    First48HoursSpO2
  GROUP BY
    stay_id
), SpO2Categories AS (
  SELECT
    stay_id,
    CASE
      WHEN avg_spo2 < 90 THEN '<90'
      WHEN avg_spo2 >= 90 AND avg_spo2 <= 92 THEN '90-92'
      WHEN avg_spo2 > 92 AND avg_spo2 <= 95 THEN '93-95'
      ELSE '>95'
    END AS spo2_category
  FROM
    AvgSpO2PerStay
), AKI AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    1 AS aki_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
  WHERE
    ie.itemid = 220187 -- Urine Output itemid
    AND ie.valuenum < 500 -- Urine output < 500 ml/24h
    AND ie.rateuom = 'mL/hr'
    AND ie.amountuom = 'mL'
    AND ie.starttime BETWEEN (
      SELECT
        ic.intime
      FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS ic
      WHERE
        ic.subject_id = ie.subject_id AND ic.stay_id = ie.stay_id
    ) AND (
      SELECT
        TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
      FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS ic
      WHERE
        ic.subject_id = ie.subject_id AND ic.stay_id = ie.stay_id
    )
)
SELECT
  sc.spo2_category,
  COUNT(DISTINCT sc.stay_id) AS patient_count,
  COUNT(DISTINCT CASE WHEN aki.aki_flag = 1 THEN aki.stay_id ELSE NULL END) AS aki_rate
FROM
  SpO2Categories AS sc
LEFT JOIN
  AKI AS aki
  ON sc.stay_id = aki.stay_id
INNER JOIN
  ICUStays AS ic
  ON sc.stay_id = ic.stay_id
INNER JOIN
  PatientDemographics AS pd
  ON ic.subject_id = pd.subject_id
WHERE
  pd.gender = 'M' AND pd.age BETWEEN 51 AND 61
GROUP BY
  sc.spo2_category
ORDER BY
  sc.spo2_category;