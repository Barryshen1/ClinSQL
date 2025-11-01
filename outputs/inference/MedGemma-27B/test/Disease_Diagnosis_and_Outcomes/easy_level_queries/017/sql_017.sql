WITH RelevantPatients AS (
  SELECT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
    AND icd.long_title LIKE '%Ischemic Stroke%'
    AND d.seq_num = 1
)
SELECT
  MAX(a.los) AS max_hospital_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN RelevantPatients AS rp
  ON a.subject_id = rp.subject_id;