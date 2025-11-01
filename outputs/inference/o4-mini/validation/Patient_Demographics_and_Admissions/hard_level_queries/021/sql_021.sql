SELECT
  COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  ON a.subject_id = d.subject_id
  AND a.hadm_id    = d.hadm_id
  AND d.seq_num    = 1
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 82 AND 92
  AND a.insurance = 'MEDICARE'
  AND LOWER(a.admission_location) LIKE '%emergency%'
  AND a.dischtime IS NOT NULL
  AND (
    (d.icd_version = 9  AND d.icd_code = '5770')
    OR
    (d.icd_version = 10 AND d.icd_code LIKE 'K85%')
  );