WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 87
),
Admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    d.long_title AS admission_diagnosis
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    )
    AND (
      d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I23%' OR d.icd_code LIKE 'I24%' OR d.icd_code LIKE 'I25%'
    )
),
LabEvents AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS troponin_t_value,
    le.valueuom AS troponin_t_uom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    le.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
      )
    AND dli.label = 'Troponin T'
    AND le.valuenum > 0.01
),
ICUStays AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  WHERE
    ic.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
      )
),
CombinedData AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    a.admission_diagnosis,
    le.charttime,
    le.troponin_t_value,
    le.troponin_t_uom,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM Admissions AS a
  INNER JOIN LabEvents AS le
    ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
  LEFT JOIN ICUStays AS ic
    ON a.subject_id = ic.subject_id AND a.hadm_id = ic.hadm_id
)
SELECT
  subject_id,
  hadm_id,
  PERCENTILE_CONT(0.25, troponin_t_value;