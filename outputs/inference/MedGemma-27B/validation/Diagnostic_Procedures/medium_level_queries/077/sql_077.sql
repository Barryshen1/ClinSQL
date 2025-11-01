WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age BETWEEN 57 AND 67
),
AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_location,
    a.discharge_location,
    a.admission_type,
    p.gender,
    p.anchor_age,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i ON a.hadm_id = i.hadm_id
),
UltrasoundEvents AS (
  SELECT
    a.hadm_id,
    a.charttime,
    a.itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` AS ad ON a.emar_id = ad.emar_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_items` AS di ON a.itemid = di.itemid
  WHERE
    di.label LIKE '%ultrasound%'
    OR di.label LIKE '%echo%'
),
UltrasoundCounts AS (
  SELECT
    ai.hadm_id,
    ai.subject_id,
    ai.gender,
    ai.anchor_age,
    ai.admittime,
    ai.dischtime,
    ai.deathtime,
    ai.hospital_expire_flag,
    ai.admission_location,
    ai.discharge_location,
    ai.admission_type,
    ai.icu_intime,
    ai.icu_outtime,
    ai.icu_los,
    COUNT(ue.itemid) AS ultrasound_count
  FROM
    AdmissionInfo AS ai
    LEFT JOIN UltrasoundEvents AS ue ON ai.hadm_id = ue.hadm_id
  WHERE
    ai.gender = 'F'
    AND ai.anchor_age BETWEEN 57 AND 67
    AND ai.admission_type = 'EMERGENCY'
    AND ai.admission_location = 'EMERGENCY ROOM'
  GROUP BY
    ai.hadm_id,
    ai.subject_id,
    ai.gender,
    ai.anchor_age,
    ai.admittime,
    ai.dischtime,
    ai.deathtime,
    ai.hospital_expire_flag,
    ai.admission_location,
    ai.discharge_location,
    ai.admission_type,
    ai.icu_intime,
    ai.icu_outtime,
    ai.icu_los
),
FinalAnalysis AS (
  SELECT
    uc.hadm_id,
    uc.subject_id,
    uc.gender,
    uc.anchor_age,
    uc.admittime,
    uc.dischtime,
    uc.deathtime,
    uc.hospital_expire_flag,
    uc.admission_location,
    uc.discharge_location,
    uc.admission_type,
    uc.icu_intime,
    uc.icu_outtime,
    uc.icu_los,
    uc.ultrasound_count,
    CASE
      WHEN uc.icu_outtime IS NOT NULL THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_status,
    CASE
      WHEN TIMESTAMP_DIFF(uc.dischtime, uc.admittime, DAY) BETWEEN 1 AND 3 THEN ';