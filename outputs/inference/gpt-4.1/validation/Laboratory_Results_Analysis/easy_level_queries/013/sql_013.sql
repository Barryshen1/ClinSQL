WITH female_copd_patients AS (
  SELECT DISTINCT p.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND (
      -- ICD-10 COPD: J44.x
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J44'))
      -- ICD-9 COPD: 491.x, 492.x, 496
      OR (d.icd_version = 9 AND (
        REGEXP_CONTAINS(d.icd_code, r'^491')
        OR REGEXP_CONTAINS(d.icd_code, r'^492')
        OR d.icd_code = '496'
      ))
    )
),
creatinine_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
    AND LOWER(fluid) = 'serum'
)
SELECT
  MAX(l.valuenum) AS max_peak_serum_creatinine_mg_dl
FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
JOIN female_copd_patients fcp
  ON l.subject_id = fcp.subject_id AND l.hadm_id = fcp.hadm_id
JOIN creatinine_itemids ci
  ON l.itemid = ci.itemid
WHERE l.valuenum IS NOT NULL
  AND LOWER(l.valueuom) = 'mg/dl';