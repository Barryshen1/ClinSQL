WITH COPD_subjects AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON p.subject_id = di.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
    ON di.icd_code = dic.icd_code
   AND di.icd_version = dic.icd_version
  WHERE LOWER(dic.long_title) LIKE '%chronic obstructive pulmonary disease%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 51
),

-- Admissions for those COPD female patients
target_admissions AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN COPD_subjects AS c ON a.subject_id = c.subject_id
)

-- Compute nadir (minimum) serum sodium per admission
SELECT STDDEV_SAMP(nadir_sodium) AS sd_nadir_sodium
FROM (
  SELECT ta.hadm_id, MIN(le.valuenum) AS nadir_sodium
  FROM target_admissions AS ta
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON ta.subject_id = le.subject_id AND ta.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE LOWER(dli.label) LIKE '%sodium%'
    AND le.valuenum IS NOT NULL
  GROUP BY ta.hadm_id
) AS nadirs;