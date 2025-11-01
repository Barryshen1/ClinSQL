WITH eligible_hadm AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age = 61
    -- Must have a pneumonia diagnosis for this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
        ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dic.long_title) LIKE '%pneumonia%'
    )
),

nadir_creatinine_per_hadm AS (
  SELECT
    eh.hadm_id,
    MIN(l.valuenum) AS nadir_creatinine
  FROM eligible_hadm AS eh
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.subject_id = eh.subject_id
   AND l.hadm_id = eh.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON l.itemid = dli.itemid
  WHERE LOWER(dli.label) LIKE '%creatinine%'
    AND l.charttime BETWEEN eh.admittime AND COALESCE(eh.dischtime, eh.admittime)
  GROUP BY eh.hadm_id
)

SELECT
  (quantiles[OFFSET(3)] - quantiles[OFFSET(1)]) AS iqr_nadir_creatinine
FROM (
  SELECT APPROX_QUANTILES(nadir_creatinine, 4) AS quantiles
  FROM nadir_creatinine_per_hadm
) AS q;