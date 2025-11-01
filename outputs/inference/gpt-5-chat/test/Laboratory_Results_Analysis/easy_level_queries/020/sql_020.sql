WITH hf_admissions AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE 
    (
      -- ICD-9 heart failure: 428.*, 402.01, 402.11, 402.91, 404.*
      (di.icd_version = 9 AND (
          di.icd_code LIKE '428%' 
          OR di.icd_code IN ('40201','40211','40291')
          OR di.icd_code LIKE '404%'))
      -- ICD-10 heart failure: I50.*, I11.0, I13.0, I13.2
      OR (di.icd_version = 10 AND (
          di.icd_code LIKE 'I50%' 
          OR di.icd_code IN ('I110','I130','I132')))
      -- As a safety net: match textual description if it contains 'HEART FAILURE'
      OR UPPER(dd.long_title) LIKE '%HEART FAILURE%'
    )
),
male_49_hf AS (
  SELECT ha.subject_id, ha.hadm_id
  FROM hf_admissions ha
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ha.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age = 49
),
hemoglobin_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE 'hemoglobin%'
    AND LOWER(fluid) = 'blood'
),
nadir_hb AS (
  SELECT
    mh.subject_id,
    mh.hadm_id,
    MIN(le.valuenum) AS nadir_hemoglobin
  FROM male_49_hf mh
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON mh.subject_id = le.subject_id
    AND mh.hadm_id = le.hadm_id
  JOIN hemoglobin_itemids hi
    ON le.itemid = hi.itemid
  WHERE le.valuenum IS NOT NULL
    AND LOWER(le.valueuom) = 'g/dl'
  GROUP BY mh.subject_id, mh.hadm_id
)
SELECT
  APPROX_QUANTILES(nadir_hemoglobin, 100)[OFFSET(75)] AS p75_nadir_hemoglobin_g_dl
FROM nadir_hb;