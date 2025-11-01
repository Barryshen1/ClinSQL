SELECT
  COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON di.subject_id = a.subject_id
  AND di.hadm_id = a.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.transfers` AS tr
  ON tr.subject_id = a.subject_id
  AND tr.hadm_id = a.hadm_id
WHERE
  p.gender = 'F'
  AND LOWER(a.insurance) LIKE '%medicare%'
  AND di.seq_num = 1
  AND (
        (di.icd_version = 9 AND di.icd_code = '427.31')
        OR (di.icd_version = 10 AND di.icd_code IN ('I48.0','I48.1','I48.2','I48.3','I48.4','I48.9'))
      )
  AND LOWER(tr.eventtype) LIKE '%transfer%';