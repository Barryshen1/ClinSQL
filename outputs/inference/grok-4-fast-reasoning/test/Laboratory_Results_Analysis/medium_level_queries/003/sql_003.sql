WITH qualifying_admissions AS (
  SELECT DISTINCT ha.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions ha
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p 
    ON ha.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di 
    ON ha.hadm_id = di.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 36 AND 46
    AND (
      (di.icd_version = 10 AND di.icd_code LIKE 'I2[0-5]%')
      OR (di.icd_version = 9 AND di.icd_code LIKE '41[0-4]%')
    )
),
troponin_events AS (
  SELECT le.hadm_id, le.charttime, le.valuenum, le.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN qualifying_admissions qa 
    ON le.hadm_id = qa.hadm_id
  WHERE le.itemid = 53522
    AND le.valuenum IS NOT NULL
),
initial_troponin AS (
  SELECT hadm_id, valuenum AS initial_troponin, ref_range_upper
  FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM troponin_events
  )
  WHERE rn = 1
)
SELECT 
  MIN(it.initial_troponin) AS min_val,
  APPROX_QUANTILES(it.initial_troponin, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(it.initial_troponin, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(it.initial_troponin, 4)[OFFSET(3)] AS p75,
  MAX(it.initial_troponin) AS max_val,
  COUNT(*) AS n_patients
FROM initial_troponin it
WHERE it.initial_troponin > it.ref_range_upper 
  AND it.ref_range_upper IS NOT NULL;