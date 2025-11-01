WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
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
), LabInfo AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS hs_tnt_value,
    l.valueuom AS hs_tnt_uom,
    d.label AS hs_tnt_label
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Troponin I, high-sensitivity'
)
SELECT
  COUNT(DISTINCT a.subject_id) AS patient_count,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(l.hs_tnt_value) AS mean_hs_tnt,
  PERCENTILE_CONT(l.hs_tnt_value, 0.5) AS median_hs_tnt,
  PERCENTILE_CONT(l.hs_tnt_value, 0.25) AS iqr_hs_tnt_25,
  PERCENTILE_CONT(l.hs_tnt_value, 0.75) AS iqr_hs_tnt_75
FROM
  PatientInfo AS p
JOIN
  AdmissionInfo AS a
  ON p.subject_id = a.subject_id
JOIN
  LabInfo AS l
  ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
WHERE
  p.gender = 'M' AND p.anchor_age BETWEEN 50 AND 60 AND (a.diagnosis LIKE '%chest pain%' OR a.diagnosis LIKE '%AMI%') AND l.hs_tnt_value > 0.014;