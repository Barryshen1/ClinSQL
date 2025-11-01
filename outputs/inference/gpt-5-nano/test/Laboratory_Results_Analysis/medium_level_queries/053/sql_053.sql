WITH
  -- Admissions for female patients aged 68-78
  acs_admissions AS (
    SELECT a.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    WHERE p.gender = 'Female'
      AND p.anchor_age BETWEEN 68 AND 78
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.subject_id = a.subject_id
          AND di.hadm_id = a.hadm_id
          AND (
            (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '411%'))
            OR (di.icd_version = 10 AND di.icd_code LIKE 'I2%')
          )
      )
  ),
  -- Troponin items (labels containing Troponin)
  troponin_items AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE LOWER(label) LIKE '%troponin%'
  ),
  -- First troponin measurement per admission
  first_troponin_per_adm AS (
    SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum, le.valueuom,
           ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id
                              ORDER BY le.charttime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN troponin_items ti ON le.itemid = ti.itemid
    WHERE le.valuenum IS NOT NULL
      AND le.charttime IS NOT NULL
  ),
  -- Keep only the first troponin per admission
  first_troponin_per_adm_1 AS (
    SELECT *
    FROM first_troponin_per_adm
    WHERE rn = 1
  )
SELECT
  COUNT(DISTINCT a.subject_id) AS patient_count,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(ft.valuenum) AS mean_troponin,
  STDDEV_POP(ft.valuenum) AS stddev_troponin,
  MIN(ft.valuenum) AS min_troponin,
  MAX(ft.valuenum) AS max_troponin
FROM acs_admissions a
JOIN first_troponin_per_adm_1 ft
  ON ft.subject_id = a.subject_id
 AND ft.hadm_id = a.hadm_id
WHERE UPPER(ft.valueuom) LIKE '%NG/ML%'
  AND ft.valuenum > 0.04
;