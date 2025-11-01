WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age = 90
),
Admissions AS (
  SELECT
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE
    subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    )
),
Diagnoses AS (
  SELECT
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    hadm_id IN (
      SELECT
        hadm_id
      FROM Admissions
    ) AND icd_code = 'J44.9'
),
RelevantAdmissions AS (
  SELECT DISTINCT
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN Diagnoses AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    a.hadm_id IN (
      SELECT
        hadm_id
      FROM Admissions
    )
),
CreatinineMeasurements AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.valuenum AS creatinine_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    le.hadm_id IN (
      SELECT
        hadm_id
      FROM RelevantAdmissions
    ) AND dli.label = 'Creatinine'
),
First24HoursCreatinine AS (
  SELECT
    hadm_id,
    creatinine_value,
    charttime
  FROM CreatinineMeasurements
  WHERE
    charttime BETWEEN (
      SELECT
        admittime
      FROM `physionet-data.mimiciv_3_1_hosp.admissions`
      WHERE
        hadm_id = CreatinineMeasurements.hadm_id
    ) AND TIMESTAMP_ADD((
      SELECT
        admittime
      FROM `physionet-data.mimiciv_3_1_hosp.admissions`
      WHERE
        hadm_id = CreatinineMeasurements.hadm_id
    ), INTERVAL 24 HOUR)
)
SELECT
  STDDEV(creatinine_value)
FROM First24HoursCreatinine;