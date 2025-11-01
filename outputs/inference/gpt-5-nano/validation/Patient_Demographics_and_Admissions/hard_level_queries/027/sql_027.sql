SELECT
  COUNT(DISTINCT a.hadm_id) AS index_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON a.subject_id = di.subject_id
  AND a.hadm_id = di.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
  ON di.icd_code = dd.icd_code
  AND di.icd_version = dd.icd_version
WHERE
  LOWER(p.gender) = 'f'
  AND p.anchor_age BETWEEN 70 AND 80
  AND UPPER(a.insurance) LIKE '%MEDICARE%'
  AND (
        LOWER(a.admission_location) LIKE '%emergency%'
        OR LOWER(a.admission_type) LIKE '%emergency%'
      )
  AND di.seq_num = 1
  AND LOWER(dd.long_title) LIKE '%acute pancreatitis%'
;