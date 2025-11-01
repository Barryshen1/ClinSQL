WITH Cohort AS (
  SELECT
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 46 AND 56
    AND a.admission_type = 'TRANSFER'
    AND d.seq_num = 1
    AND di.long_title LIKE '%hip fracture%'
    AND di.icd_version = 10 -- Changed '10' to 10 to match the integer type of icd_version
)
SELECT
  COUNT(hadm_id)
FROM Cohort;