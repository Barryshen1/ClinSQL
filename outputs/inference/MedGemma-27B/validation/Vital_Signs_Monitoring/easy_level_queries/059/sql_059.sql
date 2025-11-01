WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 77 AND 87
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
), FirstSpO2 AS (
  SELECT
    ai.subject_id,
    ai.hadm_id,
    ce.charttime,
    ce.valuenum AS spo2_value
  FROM
    AdmissionInfo AS ai
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ai.subject_id = ce.subject_id AND ai.hadm_id = ce.hadm_id
  WHERE
    ce.itemid = 220187 -- SpO2 (%)
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ai.subject_id, ai.hadm_id ORDER BY ce.charttime ASC) = 1
)
SELECT
  STDDEV(spo2_value)
FROM
  FirstSpO2;