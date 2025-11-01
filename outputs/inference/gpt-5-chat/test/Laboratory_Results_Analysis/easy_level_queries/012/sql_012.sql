WITH hemorrhagic_patients AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id
    AND adm.hadm_id = diag.hadm_id
  -- restrict to hemorrhagic stroke: ICD-9 430-432 or ICD-10 I60-I62
  WHERE pat.gender = 'F'
    AND pat.anchor_age = 87
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('430','431')
       OR (diag.icd_version = 9 AND diag.icd_code LIKE '432%'))
      OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I60%')
      OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I61%')
      OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I62%')
    )
),
platelet_labs AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE di.label = 'Platelet Count'
    AND le.valuenum IS NOT NULL
)
SELECT 
  PERCENTILE_CONT(valuenum, 0.75) OVER() AS p75_platelet_count
FROM platelet_labs pl
JOIN hemorrhagic_patients hp
  ON pl.subject_id = hp.subject_id
  AND pl.hadm_id = hp.hadm_id
-- discharge day filter
WHERE DATE(pl.charttime) = DATE(hp.dischtime)
LIMIT 1;