SELECT COUNT(*) AS num_index_admissions
FROM physionet-data.mimiciv_3_1_hosp.admissions AS adm
JOIN physionet-data.mimiciv_3_1_hosp.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS dx
  ON adm.hadm_id = dx.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS dxdesc
  ON dx.icd_code = dxdesc.icd_code AND dx.icd_version = dxdesc.icd_version
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 43 AND 53
  AND LOWER(adm.insurance) LIKE '%medicare%'
  AND (
    LOWER(adm.admission_location) LIKE '%emergency%'
    OR LOWER(adm.admission_location) LIKE '%ed%'
  )
  AND dx.seq_num = 1
  AND (
    LOWER(dxdesc.long_title) LIKE '%obstruction%'
    AND (
      LOWER(dxdesc.long_title) LIKE '%bowel%'
      OR LOWER(dxdesc.long_title) LIKE '%intestinal%'
    )
  )
  AND adm.dischtime IS NOT NULL;