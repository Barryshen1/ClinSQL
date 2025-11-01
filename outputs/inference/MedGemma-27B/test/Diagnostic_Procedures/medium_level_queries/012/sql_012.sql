WITH PatientDemographics AS (
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
    a.dischtime,
    a.los,
    a.admission_type,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientDemographics AS p
    ON a.subject_id = p.subject_id
), ACSAdmissions AS (
  SELECT
    ai.subject_id,
    ai.hadm_id,
    ai.los,
    ai.gender,
    ai.anchor_age
  FROM
    AdmissionInfo AS ai
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON ai.hadm_id = di.hadm_id
  WHERE
    di.icd_code IN ('410', '411', '414') -- ACS ICD-10 codes
), UltrasoundCounts AS (
  SELECT
    acs.hadm_id,
    COUNT(pe.itemid) AS ultrasound_count
  FROM
    ACSAdmissions AS acs
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON acs.hadm_id = pe.hadm_id
  WHERE
    pe.itemid IN (30114, 30115, 30116, 30117, 30118, 30119, 30120, 30121, 30122, 30123, 30124, 30125, 30126, 30127, 30128, 30129, 30130, 30131, 30132, 30133, 30134, 30135, 30136, 30137, 30138, 30139, 30140, 30141, 30142, 30143, 30144, 30145, 30146, 30147, 30148, 30149, 30150, 30151, 30152, 30153, 30154, 30155, 30156, 30157, 30158, 30159, 30160, 30161, 30162, 30163, 30164, 30165, 30166, 30167, 3016;