WITH acs_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 88 AND 98
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '410%')
      OR (dx.icd_version = 9 AND dx.icd_code LIKE '411%')
      OR (dx.icd_version = 10 AND (
           dx.icd_code LIKE 'I20%' OR 
           dx.icd_code LIKE 'I21%' OR 
           dx.icd_code LIKE 'I22%'
         ))
    )
),
troponin_first AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom
  FROM acs_admissions AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON a.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dl
    ON l.itemid = dl.itemid
  WHERE dl.label LIKE '%Troponin T%'
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
),
first_trop_per_adm AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum
  FROM (
    SELECT
      subject_id,
      hadm_id,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM troponin_first
  )
  WHERE rn = 1
    AND valuenum > 0.01
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS median_ng_per_ml,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS iqr_ng_per_ml
FROM first_trop_per_adm;