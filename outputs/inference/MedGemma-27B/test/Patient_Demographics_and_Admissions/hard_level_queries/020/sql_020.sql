WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 76 AND 86
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    a.hospital_expire_flag,
    a.insurance,
    d.long_title AS admission_diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE
    a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'TRANSFER FROM OTHER HOSPITAL'
    AND (
      (
        d.icd_version = 9 AND d.icd_code LIKE '410%'
      ) OR (
        d.icd_version = 10 AND d.icd_code LIKE 'I21%'
      )
    )
), ReadmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime AS index_admittime,
    a.dischtime AS index_dischtime,
    a.deathtime AS index_deathtime,
    a.hospital_expire_flag AS index_hospital_expire_flag,
    a.insurance AS index_insurance,
    a.admission_diagnosis AS index_admission_diagnosis,
    b.hadm_id AS readmission_hadm_id,
    b.admittime AS readmission_admittime,
    b.dischtime AS readmission_dischtime,
    b.deathtime AS readmission_deathtime,
    b.hospital_expire_flag AS readmission_hospital_expire_flag,
    b.insurance AS readmission_insurance,
    b.admission_diagnosis AS readmission_admission_diagnosis
  FROM
    AdmissionInfo AS a
  LEFT JOIN
    AdmissionInfo AS b
    ON a.subject_id = b.subject_id
    AND b.admittime > a.dischtime
    AND b.admittime <= TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
), IndexLOS AS (
  SELECT
    subject_id,
    hadm_id,
    index_admittime,
    index_dischtime,
    index_deathtime,
    index_hospital_expire_flag,
    CASE
      WHEN index_deathtime IS NOT NULL THEN TIMESTAMP_DIFF(index_deathtime, index_admittime, DAY)
      ELSE TIMESTAMP_DIFF(index_dischtime, index_admittime, DAY)
    END AS index_los
  FROM
    AdmissionInfo
), ReadmissionStatus AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN readmission_hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmitted
  FROM
    ReadmissionInfo
), IndexStayDuration AS (
  SELECT
    subject_id,
    hadm_id,
    index_los,
    CASE
      WHEN index_los > 4 THEN 1
      ELSE 0
    END AS index_stay_gt_4_days
  FROM
    IndexLOS
)
SELECT
  AVG(readmitted) AS thirty_day_readmission_rate,
  AVG(CASE WHEN readmitted = 1 THEN index_los ELSE NULL END) AS median_index_los_readmitted,
  AVG(CASE WHEN readmitted = 0 THEN index_los ELSE NULL END) AS median_index_los_not_readmitted,
  AVG(index_stay_gt_4_days) AS percent_index_stays_gt_4_days
FROM
  ReadmissionStatus AS rs
LEFT JOIN;