WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 55 AND 65
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    d.long_title LIKE '%AMI%'
), TnTInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    le.charttime,
    le.valuenum AS hs_tnt_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON a.hadm_id = le.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'hs-TnT'
    AND le.valuenum > 0.01
)
SELECT
  COUNT(DISTINCT a.subject_id) AS patient_count,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(t.hs_tnt_value) AS hs_tnt_mean,
  APPROX_QUANTILES(t.hs_tnt_value, 4)[OFFSET(1)] AS hs_tnt_median,
  APPROX_QUANTILES(t.hs_tnt_value, 4)[OFFSET(0)] AS hs_tnt_iqr_25,
  APPROX_QUANTILES(t.hs_tnt_value, 4)[OFFSET(2)] AS hs_tnt_iqr_75
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  PatientInfo AS pi
  ON a.subject_id = pi.subject_id
JOIN
  AdmissionInfo AS ai
  ON a.hadm_id = ai.hadm_id
JOIN
  TnTInfo AS t
  ON a.hadm_id = t.hadm_id;