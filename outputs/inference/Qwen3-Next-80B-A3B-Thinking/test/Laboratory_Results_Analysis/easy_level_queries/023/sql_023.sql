WITH lactate_measurements AS (
  SELECT
    labevents.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
    ON patients.subject_id = admissions.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diagnoses_icd
    ON admissions.hadm_id = diagnoses_icd.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_icd_diagnoses
    ON diagnoses_icd.icd_code = d_icd_diagnoses.icd_code
    AND diagnoses_icd.icd_version = d_icd_diagnoses.icd_version
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS labevents
    ON admissions.hadm_id = labevents.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d_labitems
    ON labevents.itemid = d_labitems.itemid
  WHERE
    patients.gender = 'M'
    AND (
      d_icd_diagnoses.long_title LIKE '%sepsis%'
      OR d_icd_diagnoses.long_title LIKE '%septicemia%'
      OR d_icd_diagnoses.long_title LIKE '%septic shock%'
    )
    AND DATE(labevents.charttime) = DATE(admissions.dischtime)
    AND d_labitems.label LIKE '%lactate%'
    AND labevents.valuenum IS NOT NULL
)
SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS iqr
FROM
  lactate_measurements;