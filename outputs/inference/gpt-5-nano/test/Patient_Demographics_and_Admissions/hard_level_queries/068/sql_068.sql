SELECT COUNT(DISTINCT a.hadm_id) AS admissions_count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON a.subject_id = di.subject_id
  AND a.hadm_id = di.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
  ON di.icd_code = dd.icd_code
  AND di.icd_version = dd.icd_version
WHERE LOWER(a.admission_location) LIKE '%snf%'
  AND di.seq_num = 1
  AND LOWER(a.insurance) LIKE '%medicare%'
  AND p.gender = 'M'
  AND (CAST(p.anchor_age AS INT64)
       + (EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64)))
      BETWEEN 43 AND 53
  AND LOWER(dd.long_title) LIKE '%dehydration%';