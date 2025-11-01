SELECT COUNT(DISTINCT a.hadm_id) AS cohort_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON a.subject_id = di.subject_id
 AND a.hadm_id = di.hadm_id
WHERE
  di.seq_num = 1
  AND (
    (di.icd_version = 9 AND di.icd_code = '577.0')
    OR (di.icd_version = 10 AND di.icd_code LIKE 'K85%')
  )
  AND a.edregtime IS NOT NULL
  AND a.dischtime IS NOT NULL
  AND LOWER(a.insurance) LIKE '%medicare%'
  AND p.anchor_age BETWEEN 82 AND 92
  AND (UPPER(p.gender) = 'F' OR UPPER(p.gender) = 'FEMALE');