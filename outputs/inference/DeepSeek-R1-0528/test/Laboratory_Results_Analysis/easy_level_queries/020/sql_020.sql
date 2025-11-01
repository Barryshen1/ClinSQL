WITH hf_admissions AS (
  SELECT DISTINCT
      p.subject_id,
      a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  WHERE
      p.gender = 'M'
      AND p.anchor_age = 49
      AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%') OR
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
      )
),
nadir_hemoglobin AS (
  SELECT
      ha.hadm_id,
      MIN(le.valuenum) AS nadir_hgb
  FROM hf_admissions ha
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON ha.subject_id = le.subject_id AND ha.hadm_id = le.hadm_id
  WHERE
      le.itemid = 51222  -- Hemoglobin
      AND le.valuenum IS NOT NULL
  GROUP BY ha.hadm_id
)
SELECT
  APPROX_QUANTILES(nadir_hgb, 100)[OFFSET(75)] AS p75_nadir_hemoglobin
FROM nadir_hemoglobin;