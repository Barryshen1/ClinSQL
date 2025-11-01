WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), DiagnosisInfo AS (
  SELECT
    hadm_id,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_version = 9
    AND icd_code LIKE '410%'
), LabInfo AS (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum AS troponin_t_value,
    valueuom AS troponin_t_uom
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE
    itemid = 50178 -- Troponin T
), FirstTroponin AS (
  SELECT
    li.subject_id,
    li.hadm_id,
    li.charttime,
    li.troponin_t_value,
    li.troponin_t_uom
  FROM
    LabInfo li
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY li.subject_id, li.hadm_id ORDER BY li.charttime ASC) = 1
)
SELECT
  PERCENTILE_CONT(0.5, ft.troponin_t_value) AS median_troponin_t,
  PERCENTILE_CONT(0.25, ft.troponin_t_value) AS iqr_troponin_t_25,
  PERCENTILE_CONT(0.75, ft.troponin_t_value) AS iqr_troponin_t_75
FROM
  FirstTroponin ft
INNER JOIN
  AdmissionInfo ai ON ft.hadm_id = ai.hadm_id
INNER JOIN
  PatientInfo pi ON ft.subject_id = pi.subject_id
INNER JOIN
  DiagnosisInfo di ON ft.hadm_id = di.hadm_id
WHERE
  pi.gender = 'F'
  AND pi.anchor_age BETWEEN 88 AND 98
  AND ft.troponin_t_value > 0.01
  AND ft.troponin_t_uom = 'ng/mL';