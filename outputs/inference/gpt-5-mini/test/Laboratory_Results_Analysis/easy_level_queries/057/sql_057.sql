WITH creat_itemids AS (
  -- creatinine lab itemids (labels containing 'creatinine')
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
),

nadir_creatinine_per_adm AS (
  -- nadir (minimum) creatinine per hospital admission
  SELECT
    le.hadm_id,
    MIN(le.valuenum) AS nadir_creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN creat_itemids d
    ON le.itemid = d.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.valuenum > 0
  GROUP BY le.hadm_id
),

pneumonia_admissions AS (
  -- admissions with any diagnosis whose label contains 'pneumonia'
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pneumonia%'
),

eligible_admissions AS (
  -- join cohort: male, age 61, pneumonia, and with nadir creatinine
  SELECT n.hadm_id, n.nadir_creatinine
  FROM nadir_creatinine_per_adm n
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON n.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN pneumonia_admissions pa
    ON n.hadm_id = pa.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age = 61
)

SELECT
  quantiles[SAFE_OFFSET(1)] AS q1_nadir_creatinine,
  quantiles[SAFE_OFFSET(3)] AS q3_nadir_creatinine,
  quantiles[SAFE_OFFSET(3)] - quantiles[SAFE_OFFSET(1)] AS iqr_nadir_creatinine,
  cnt_rows AS n_admissions_included
FROM (
  SELECT
    APPROX_QUANTILES(nadir_creatinine, 4) AS quantiles,
    COUNT(*) AS cnt_rows
  FROM eligible_admissions
);