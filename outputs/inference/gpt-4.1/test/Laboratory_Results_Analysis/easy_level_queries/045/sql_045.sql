WITH sepsis_icd_codes AS (
  -- List of ICD codes for sepsis (ICD-9 and ICD-10)
  SELECT '99591' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '99592', 9 UNION ALL
  SELECT '78552', 9 UNION ALL
  SELECT 'A40', 10 UNION ALL
  SELECT 'A41', 10
),
male_83_sepsis_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime
  FROM physionet-data.mimiciv_3_1_hosp.admissions adm
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON adm.subject_id = pat.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
    ON adm.hadm_id = diag.hadm_id
  JOIN sepsis_icd_codes sicd
    ON diag.icd_code LIKE CONCAT(sicd.icd_code, '%') AND diag.icd_version = sicd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age = 83
),
creatinine_itemids AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) LIKE '%creatinine%'
    AND LOWER(fluid) = 'blood'
),
index_creatinine AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    MIN(lab.charttime) AS index_charttime
  FROM male_83_sepsis_admissions adm
  JOIN physionet-data.mimiciv_3_1_hosp.labevents lab
    ON adm.hadm_id = lab.hadm_id
  JOIN creatinine_itemids ci
    ON lab.itemid = ci.itemid
  WHERE lab.charttime >= adm.admittime
  GROUP BY adm.subject_id, adm.hadm_id
),
index_creatinine_values AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    lab.valuenum
  FROM index_creatinine ic
  JOIN physionet-data.mimiciv_3_1_hosp.labevents lab
    ON ic.hadm_id = lab.hadm_id
    AND lab.charttime = ic.index_charttime
  JOIN creatinine_itemids ci
    ON lab.itemid = ci.itemid
  WHERE lab.valuenum IS NOT NULL
)
SELECT
  MAX(valuenum) AS max_index_serum_creatinine
FROM index_creatinine_values;