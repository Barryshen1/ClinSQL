SELECT
  MAX(lv.valuenum) AS max_creatinine_mg_per_dl
FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS lv
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS labi
  ON lv.itemid = labi.itemid
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON lv.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON di.subject_id = lv.subject_id
  AND di.hadm_id = lv.hadm_id
WHERE
  (UPPER(p.gender) = 'F' OR UPPER(p.gender) = 'FEMALE')
  AND (
    (di.icd_version = 9 AND (di.icd_code LIKE '491%' OR di.icd_code LIKE '492%' OR di.icd_code LIKE '496%'))
    OR
    (di.icd_version = 10 AND di.icd_code LIKE 'J44%')
  )
  AND LOWER(labi.label) LIKE '%creatinine%'
  AND LOWER(lv.valueuom) = 'mg/dl';