WITH PatientAgeGroup AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 62 AND 72
),
FirstSpO2 AS (
  SELECT
    ce.subject_id,
    MIN(ce.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN PatientAgeGroup AS pag
    ON ce.subject_id = pag.subject_id
  WHERE
    ce.itemid = 220187 -- SpO2 itemid
  GROUP BY
    ce.subject_id
)
SELECT
  PERCENTILE_CONT(0.25, spo2.valuenum) AS iqr_25,
  PERCENTILE_CONT(0.75, spo2.valuenum) AS iqr_75
FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS spo2
JOIN FirstSpO2
  ON spo2.subject_id = FirstSpO2.subject_id AND spo2.charttime = FirstSpO2.first_charttime;