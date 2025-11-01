WITH PatientDemographics AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age,
    a.admittime,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 59 AND 69
), ShockDiagnosis AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%shock%'
    AND d.seq_num = 1
), ICUStayInfo AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    i.first_careunit
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  INNER JOIN PatientDemographics AS pd
    ON i.subject_id = pd.subject_id AND i.hadm_id = pd.hadm_id
), VitalSigns AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.value AS value,
    c.valuenum AS valuenum,
    c.valueuom AS valueuom
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  INNER JOIN ICUStayInfo AS isi
    ON c.subject_id = isi.subject_id AND c.hadm_id = isi.hadm_id AND c.stay_id = isi.stay_id
  WHERE
    c.itemid IN (
      -- MAP
      455, 566, 669, 1132, 220187, 220190, 220191, 220192, 220193, 220194, 220195, 220196, 220197, 220198, 220199, 220200, 220201, 220202
    ),
  -- HR
  c.itemid IN (
    211, 220180, 220181, 220182, 220183, 220184, 220185, 220186, 220187, 220188, 220189, 220190, 220191, 220192, 220193, 220194, 220195, 220196, 220197, 220198, 220199, 220200, 220201, 220202
  )
), ShockPatients AS (
  SELECT
    pd.subject_id,
    pd.hadm_id,
    pd.age,
    pd.gender,;