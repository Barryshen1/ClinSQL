WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 58 AND 68
), AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    d.long_title AS admission_diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    (
      LOWER(d.long_title) LIKE '%chest pain%' OR LOWER(d.long_title) LIKE '%ami%' OR LOWER(d.long_title) LIKE '%myocardial infarction%'
    )
), LabInfo AS (
  SELECT
    l.hadm_id,
    l.subject_id,
    l.charttime,
    l.valuenum AS troponin_t_value,
    l.valueuom AS troponin_t_uom
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Troponin T' AND l.valuenum > 0.04
)
SELECT
  COUNT(DISTINCT a.hadm_id) AS total_admissions,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS total_deaths,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT a.hadm_id) AS mortality_rate
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON a.hadm_id = di.hadm_id AND di.seq_num = 1
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
  ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  ON a.hadm_id = l.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dl
  ON l.itemid = dl.itemid
WHERE
  p.gender = 'M' AND p.anchor_age BETWEEN 58 AND 68 AND (LOWER(d.long_title) LIKE '%chest pain%' OR LOWER(d.long_title) LIKE '%ami%' OR LOWER(d.long_title) LIKE '%myocardial infarction%') AND dl.label = 'Troponin T' AND l.valuenum > 0.04
GROUP BY
  a.hadm_id;