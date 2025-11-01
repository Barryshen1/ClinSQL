WITH sepsis_hadm AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.gender, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
    AND a.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND UPPER(dd.long_title) LIKE '%SEPSIS%'
),
lactate_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE UPPER(label) LIKE '%LACTATE%'
    AND UPPER(fluid) = 'BLOOD'
),
lactate_on_discharge AS (
  SELECT l.valuenum
  FROM sepsis_hadm sh
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON sh.hadm_id = l.hadm_id
    AND sh.subject_id = l.subject_id
  WHERE l.itemid IN (SELECT itemid FROM lactate_items)
    AND l.valuenum IS NOT NULL
    AND DATE(l.charttime) = DATE(sh.dischtime)
)
SELECT
  quartiles[OFFSET(3)] - quartiles[OFFSET(1)] AS lactate_IQR,
  quartiles[OFFSET(1)] AS Q1,
  quartiles[OFFSET(3)] AS Q3
FROM (
  SELECT APPROX_QUANTILES(valuenum, 4) AS quartiles
  FROM lactate_on_discharge
) q;