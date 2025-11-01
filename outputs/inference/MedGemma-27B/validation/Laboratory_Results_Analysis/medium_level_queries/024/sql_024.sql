WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 64 AND 74
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    d.long_title AS admission_diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE
    d.icd_code = 'I20' -- Chest pain
), TroponinInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    le.charttime,
    le.valuenum AS troponin_value,
    le.valueuom AS troponin_uom
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON a.hadm_id = le.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Troponin T, high-sensitivity'
), TroponinPercentile AS (
  SELECT
    subject_id,
    hadm_id,
    troponin_value,
    PERCENTILE_CONT(troponin_value, 0.99) OVER (PARTITION BY subject_id, hadm_id) AS troponin_99th_percentile
  FROM
    TroponinInfo
), FinalCohort AS (
  SELECT
    pi.subject_id,
    ai.hadm_id,
    ai.hospital_expire_flag,
    tp.troponin_value,
    tp.troponin_99th_percentile
  FROM
    PatientInfo AS pi
  JOIN
    AdmissionInfo AS ai
    ON pi.subject_id = ai.subject_id
  JOIN
    TroponinPercentile AS tp
    ON pi.subject_id = tp.subject_id AND ai.hadm_id = tp.hadm_id
  WHERE
    tp.troponin_value > tp.troponin_99th_percentile
)
SELECT
  COUNT(subject_id) AS total_patients,
  AVG(troponin_value) AS avg_troponin_value,
  STDDEV(troponin_value) AS stddev_troponin_value,
  SUM(hospital_expire_flag) AS total_deaths,
  AVG(hospital_expire_flag) AS mortality_rate
FROM
  FinalCohort;