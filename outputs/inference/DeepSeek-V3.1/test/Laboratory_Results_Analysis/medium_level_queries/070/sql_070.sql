WITH chest_pain_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND d.long_title LIKE '%chest pain%'
),
first_elevated_troponin AS (
  SELECT 
    le.hadm_id,
    FIRST_VALUE(le.valuenum) OVER (
      PARTITION BY le.hadm_id 
      ORDER BY le.charttime
    ) AS first_troponin_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN chest_pain_admissions cpa
    ON le.hadm_id = cpa.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.label = 'Troponin I'
    AND le.valuenum IS NOT NULL
    AND (le.valuenum > le.ref_range_upper OR le.flag = 'abnormal')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
)
SELECT 
  APPROX_QUANTILES(first_troponin_value, 100) [OFFSET(25)] AS p25,
  APPROX_QUANTILES(first_troponin_value, 100) [OFFSET(50)] AS p50,
  APPROX_QUANTILES(first_troponin_value, 100) [OFFSET(75)] AS p75,
  MIN(first_troponin_value) AS min_value,
  MAX(first_troponin_value) AS max_value
FROM first_elevated_troponin;