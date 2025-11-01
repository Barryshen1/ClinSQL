WITH creat_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
),
copd_hadms AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND (
      LOWER(dd.long_title) LIKE '%copd%'
      OR LOWER(dd.long_title) LIKE '%chronic obstructive%'
      OR LOWER(dd.long_title) LIKE '%chronic bronchitis%'
      OR LOWER(dd.long_title) LIKE '%emphysema%'
    )
)
SELECT
  MAX(le.valuenum) AS max_peak_serum_creatinine_mg_per_dL
FROM copd_hadms ch
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON ch.hadm_id = le.hadm_id
JOIN creat_items ci
  ON le.itemid = ci.itemid
WHERE le.valuenum IS NOT NULL
  AND le.valuenum > 0
  AND le.charttime BETWEEN ch.admittime AND ch.dischtime
  AND LOWER(le.valueuom) LIKE '%mg/dl%';