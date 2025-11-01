SELECT COUNT(DISTINCT a.hadm_id) AS completed_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
  ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
WHERE UPPER(p.gender) = 'F'
  AND p.anchor_age BETWEEN 43 AND 53
  AND UPPER(a.insurance) LIKE '%MEDICARE%'
  AND UPPER(a.admission_type) = 'EMERGENCY'
  AND di.seq_num = 1
  AND (
        UPPER(dd.long_title) LIKE '%BOWEL OBSTRUCTION%' OR
        UPPER(dd.long_title) LIKE '%INTESTINAL OBSTRUCTION%'
      )
  AND a.dischtime IS NOT NULL;