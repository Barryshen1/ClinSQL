SELECT MAX(count_procedures) AS max_distinct_procedures
FROM (
  SELECT p.subject_id, a.hadm_id, COUNT(DISTINCT pi.icd_code) AS count_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON a.hadm_id = pi.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
    AND LOWER(dip.long_title) LIKE '%echocardiography%'
  GROUP BY p.subject_id, a.hadm_id
) subquery;