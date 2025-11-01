WITH ACS_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND (
      LOWER(dd.long_title) LIKE '%acute myocardial infarction%' OR
      LOWER(dd.long_title) LIKE '%myocardial infarction%' OR
      LOWER(dd.long_title) LIKE '%unstable angina%'
    )
),
Troponin_T_events AS (
  SELECT
    a.hadm_id,
    le.charttime,
    le.valuenum AS troponin_value
  FROM ACS_admissions AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = a.subject_id
   AND le.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE LOWER(dli.label) LIKE '%troponin%'
    AND (LOWER(dli.label) LIKE '%troponin t%' OR LOWER(dli.label) LIKE '%troponin_t%')
    AND le.valuenum IS NOT NULL
),
First_troponin AS (
  SELECT hadm_id, troponin_value
  FROM (
    SELECT
      hadm_id,
      charttime,
      troponin_value,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM Troponin_T_events
  )
  WHERE rn = 1
    AND troponin_value > 0.01
)
SELECT
  quantiles[OFFSET(2)] AS median_first_troponin,
  (quantiles[OFFSET(3)] - quantiles[OFFSET(1)]) AS iqr_first_troponin
FROM (
  SELECT APPROX_QUANTILES(troponin_value, 4) AS quantiles
  FROM First_troponin
) AS q;