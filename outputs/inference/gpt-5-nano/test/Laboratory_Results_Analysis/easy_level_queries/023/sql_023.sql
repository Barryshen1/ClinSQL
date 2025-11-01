WITH
  -- Lactate measurements in serum
  lactate_items AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE LOWER(label) LIKE '%lactate%'
      AND LOWER(fluid) LIKE '%serum%'
  ),
  -- Sepsis hospitalizations in males
  sepsis_hosp AS (
    SELECT DISTINCT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
      ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
    WHERE p.gender = 'Male'
      AND (LOWER(dic.long_title) LIKE '%sepsis%'
           OR LOWER(dic.long_title) LIKE '%septicemia%')
  ),
  -- Lactate measurements on discharge day for septic, male patients
  lactate_vals AS (
    SELECT l.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    JOIN lactate_items AS li ON l.itemid = li.itemid
    JOIN sepsis_hosp AS s ON l.hadm_id = s.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON l.hadm_id = a.hadm_id
    WHERE l.valuenum IS NOT NULL
      AND DATE(l.charttime) = DATE(a.dischtime)
  )
SELECT
  quantiles[OFFSET(1)] AS lactate_q1,
  quantiles[OFFSET(3)] AS lactate_q3,
  (quantiles[OFFSET(3)] - quantiles[OFFSET(1)]) AS lactate_iqr
FROM (
  SELECT APPROX_QUANTILES(valuenum, 4) AS quantiles
  FROM lactate_vals
);