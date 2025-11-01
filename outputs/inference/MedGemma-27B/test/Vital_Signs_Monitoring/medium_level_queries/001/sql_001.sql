WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 50
    AND gender = 'F'
), ICUStays AS (
  SELECT
    ic.subject_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON ic.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
), SBPMeasurements AS (
  SELECT
    ic.subject_id,
    ic.stay_id,
    ce.charttime,
    ce.valuenum AS sbp
  FROM
    ICUStays AS ic
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON ic.subject_id = ce.subject_id
      AND ic.stay_id = ce.stay_id
  WHERE
    ce.itemid = 455 -- Systolic Blood Pressure
    AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 24 HOUR)
), AvgSBP AS (
  SELECT
    subject_id,
    stay_id,
    AVG(sbp) AS avg_sbp
  FROM
    SBPMeasurements
  GROUP BY
    subject_id,
    stay_id
)
SELECT
  CASE
    WHEN avg_sbp < 140 THEN '<140'
    WHEN avg_sbp BETWEEN 140 AND 159 THEN '140–159'
    ELSE '≥160'
  END AS sbp_category,
  COUNT(DISTINCT subject_id) AS unique_patient_count
FROM
  AvgSBP
GROUP BY
  sbp_category
ORDER BY
  CASE
    WHEN sbp_category = '<140' THEN 1
    WHEN sbp_category = '140–159' THEN 2
    WHEN sbp_category = '≥160' THEN 3
  END;