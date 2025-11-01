WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 36 AND 46
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
    d.long_title LIKE '%ischemic heart disease%'
), LabInfo AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS troponin_t_value,
    l.valueuom AS troponin_t_uom,
    d.label AS troponin_t_label,
    d.unitname AS troponin_t_unit
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Troponin T, high sensitivity'
), TroponinThreshold AS (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    troponin_t_value,
    troponin_t_uom,
    troponin_t_label,
    troponin_t_unit
  FROM
    LabInfo
  WHERE
    troponin_t_uom = 'ng/L'
    AND troponin_t_value > 0.014 -- Assuming ULN for ng/L is 0.014 ng/L
)
SELECT
  PERCENTILE_CONT(0.25, troponin_t_value) AS p25,
  PERCENTILE_CONT(0.50, troponin_t_value) AS p50,
  PERCENTILE_CONT(0.75, troponin_t_value) AS p75,
  MIN(troponin_t_value) AS min_troponin_t,
  MAX(troponin_t_value) AS max_troponin_t
FROM
  TroponinThreshold;