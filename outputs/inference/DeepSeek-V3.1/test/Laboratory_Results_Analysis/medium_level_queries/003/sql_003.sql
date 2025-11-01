WITH cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    adm.hadm_id,
    adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 36 AND 46
    AND diag.icd_code LIKE 'I2[0-5]%'
    AND diag.icd_version = 10
),
first_troponin AS (
  SELECT
    c.hadm_id,
    le.charttime,
    le.valuenum AS troponin_value,
    le.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY le.charttime) AS rn
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE
    dli.loinc_code = '6598-7'
    AND le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND le.valuenum > le.ref_range_upper
)
SELECT
  MIN(troponin_value) AS min_value,
  MAX(troponin_value) AS max_value,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(75)] AS p75
FROM first_troponin
WHERE rn = 1;