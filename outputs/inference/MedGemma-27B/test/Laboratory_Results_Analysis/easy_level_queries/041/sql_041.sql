WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age = 52
),
Admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientInfo AS p
    ON a.subject_id = p.subject_id
),
Diagnoses AS (
  SELECT
    d.hadm_id,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN Admissions AS a
    ON d.hadm_id = a.hadm_id
  WHERE
    d.icd_code LIKE 'J18%' -- Pneumonia codes
),
ICUStays AS (
  SELECT
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN Admissions AS a
    ON i.hadm_id = a.hadm_id
  JOIN Diagnoses AS diag
    ON i.hadm_id = diag.hadm_id
),
CreatinineMeasurements AS (
  SELECT
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS creatinine_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  JOIN ICUStays AS i
    ON c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS d
    ON c.itemid = d.itemid
  WHERE
    d.label = 'Creatinine' AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
)
SELECT
  STDDEV(creatinine_value)
FROM CreatinineMeasurements;