WITH sepsis_admissions AS (
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE LOWER(d_diag.long_title) LIKE '%sepsis%'
),
male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
platelet_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) = 'platelets'
),
first_platelets AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  CROSS JOIN platelet_item pi
  INNER JOIN sepsis_admissions sa ON le.hadm_id = sa.hadm_id
  INNER JOIN male_patients mp ON le.subject_id = mp.subject_id
  WHERE le.itemid = pi.itemid
    AND le.valuenum IS NOT NULL
    AND le.charttime >= (SELECT admittime FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm WHERE adm.hadm_id = le.hadm_id)
)
SELECT
  STDDEV(valuenum) AS platelet_count_stddev
FROM first_platelets
WHERE rn = 1;