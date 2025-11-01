WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 49 AND 59
), PatientDiagnosis AS (
  SELECT
    p.subject_id,
    p.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON d.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M' AND p.anchor_age = 54 AND d.seq_num = 1 AND di.long_title LIKE '%heart failure%'
), ICUStay AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.icustays` AS i ON a.hadm_id = i.hadm_id
), CT_MRI AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT hc.hcpcs_cd) AS ct_mri_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hc ON a.hadm_id = hc.hadm_id
  WHERE
    hc.hcpcs_cd IN ('77002', '77003', '77059', '77061', '77062', '77063', '77064', '77065', '77066', '77067', '77068', '77069', '77071', '77072', '77073', '77074', '77075', '77076', '77077', '77078', '77079', '77080', '77081', '77082', '77083', '77084', '77085', '77086', '77087', '77088', '77089', '77090', '77091', '77092', '77093',;