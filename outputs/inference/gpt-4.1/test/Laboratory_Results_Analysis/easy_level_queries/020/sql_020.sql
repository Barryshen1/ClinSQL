WITH heart_failure_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    -- ICD-10: I50*, ICD-9: 428*
    (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '428')
    OR (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'I50')
),
male_49_hadm AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age = 49
),
hemoglobin_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) = 'hemoglobin'
),
nadir_hgb_per_hadm AS (
  SELECT
    l.hadm_id,
    MIN(l.valuenum) AS nadir_hgb
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN hemoglobin_itemids hgb ON l.itemid = hgb.itemid
  JOIN male_49_hadm m ON l.hadm_id = m.hadm_id
  JOIN heart_failure_hadm hf ON l.hadm_id = hf.hadm_id
  WHERE
    l.valuenum IS NOT NULL
    AND l.charttime BETWEEN m.admittime AND m.dischtime
  GROUP BY l.hadm_id
)
SELECT
  PERCENTILE_CONT(nadir_hgb, 0.75) OVER() AS nadir_hgb_75th_percentile
FROM nadir_hgb_per_hadm
;