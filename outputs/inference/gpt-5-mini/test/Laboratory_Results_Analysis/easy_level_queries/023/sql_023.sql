WITH lactate_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%lactat%'  -- captures "lactate", "lactic acid", etc.
),

sepsis_male_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND LOWER(dd.long_title) LIKE '%sepsis%'  -- identifies sepsis diagnoses (ICD-9/10)
),

lactate_on_discharge_day AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN lactate_items li
    ON le.itemid = li.itemid
  JOIN sepsis_male_admissions sa
    ON le.hadm_id = sa.hadm_id
   AND le.subject_id = sa.subject_id
  WHERE le.valuenum IS NOT NULL
    -- measurement occurred on the same calendar day as the admission discharge
    AND DATE(le.charttime) = DATE(sa.dischtime)
)

SELECT
  stats.n_values,
  stats.quantiles[OFFSET(1)] AS q1,
  stats.quantiles[OFFSET(3)] AS q3,
  stats.quantiles[OFFSET(3)] - stats.quantiles[OFFSET(1)] AS iqr
FROM (
  SELECT
    COUNT(*) AS n_values,
    APPROX_QUANTILES(valuenum, 4) AS quantiles  -- returns [min, Q1, median, Q3, max]
  FROM lactate_on_discharge_day
) AS stats;