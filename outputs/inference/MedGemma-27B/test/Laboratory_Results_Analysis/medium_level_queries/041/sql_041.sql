WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
),
AdmissionInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),
DiagnosisInfo AS (
  SELECT
    hadm_id,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    seq_num = 1
),
LabInfo AS (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    itemid,
    valuenum,
    valueuom
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents`
),
TroponinInfo AS (
  SELECT
    li.subject_id,
    li.hadm_id,
    li.charttime,
    li.valuenum AS troponin_value,
    li.valueuom AS troponin_uom,
    li.itemid -- Added itemid here
  FROM
    LabInfo AS li
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli ON li.itemid = dli.itemid
  WHERE
    dli.label = 'Troponin T, high sensitivity'
),
FirstTroponin AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS first_troponin_time,
    troponin_value,
    troponin_uom,
    itemid -- Added itemid here
  FROM
    TroponinInfo
  GROUP BY
    subject_id,
    hadm_id,
    troponin_value,
    troponin_uom,
    itemid -- Added itemid here
),
UpperLimit AS (
  SELECT
    itemid,
    MAX(ref_range_upper) AS upper_limit
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE
    itemid = (
      SELECT
        itemid
      FROM
        `physionet-data.mimiciv_3_1_hosp.d_labitems`
      WHERE
        label = 'Troponin T, high sensitivity'
    )
  GROUP BY
    itemid
),
ACS_Patients AS (
  SELECT
    ai.subject_id,
    ai.hadm_id
  FROM
    AdmissionInfo AS ai
  JOIN
    DiagnosisInfo AS di ON ai.hadm_id = di.hadm_id
  WHERE
    di.icd_code LIKE 'I21%'
),
EligiblePatients AS (
  SELECT
    acs.subject_id,
    acs.hadm_id,
    pi.gender,
    pi.anchor_age,
    ft.troponin_value,
    ft.troponin_uom,
    ul.upper_limit
  FROM
    ACS_Patients AS acs
  JOIN
    PatientInfo AS pi ON acs.subject_id = pi.subject_id
  JOIN
    FirstTroponin AS ft ON acs.subject_id = ft.subject_id AND acs.hadm_id = ft.hadm_id
  JOIN
    UpperLimit AS ul ON ft.itemid = ul.itemid -- Corrected join condition;