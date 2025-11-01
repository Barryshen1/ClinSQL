WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age = 42
),
AdmissionsWithAKI AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'N17%' -- AKI codes
),
FilteredAdmissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM AdmissionsWithAKI AS a
  INNER JOIN PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.admittime BETWEEN TIMESTAMP('2000-01-01') AND TIMESTAMP('2023-12-31') -- Filter for relevant time period
),
HospitalLOS AS (
  SELECT
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM FilteredAdmissions
)
SELECT
  PERCENTILE_CONT(los_days, 0.75) AS percentile_75_los
FROM HospitalLOS;