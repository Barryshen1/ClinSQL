WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 63
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag ON a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    diag.seq_num = 1
), TroponinInfo AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS troponin_t_value,
    le.valueuom AS troponin_t_uom
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Troponin T'
), FirstTroponin AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS first_troponin_time
  FROM
    TroponinInfo
  GROUP BY
    subject_id,
    hadm_id
), FirstTroponinValue AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.troponin_t_value,
    t.troponin_t_uom
  FROM
    TroponinInfo AS t
  JOIN
    FirstTroponin AS ft ON t.subject_id = ft.subject_id AND t.hadm_id = ft.hadm_id AND t.charttime = ft.first_troponin_time
)
SELECT
  AVG(ftv.troponin_t_value) AS mean_troponin_t,
  STDDEV(ftv.troponin_t_value) AS sd_troponin_t,
  MIN(ftv.troponin_t_value) AS min_troponin_t,
  MAX(ftv.troponin_t_value) AS max_troponin_t
FROM
  FirstTroponinValue AS ftv
JOIN
  AdmissionInfo AS ai ON ftv.subject_id = ai.subject_id AND ftv.hadm_id = ai.hadm_id
JOIN
  PatientInfo AS pi ON ftv.subject_id = pi.subject_id
WHERE
  pi.gender = 'F'
  AND pi.anchor_age BETWEEN 58 AND 68
  AND ai.diagnosis LIKE '%chest pain%' OR ai.diagnosis LIKE '%AMI%'
  AND ftv.troponin_t_value > 0.01
  AND ftv.troponin_t_uom = 'ng/mL';