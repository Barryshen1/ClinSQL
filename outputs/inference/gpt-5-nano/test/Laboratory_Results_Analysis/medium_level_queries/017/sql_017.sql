WITH ischemic_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 47 AND 57
    AND (
      (di.icd_version = 10 AND di.icd_code LIKE 'I2%')
      OR (di.icd_version = 9 AND (
            di.icd_code LIKE '410%' OR di.icd_code LIKE '411%' OR di.icd_code LIKE '412%' OR
            di.icd_code LIKE '413%' OR di.icd_code LIKE '414%'
         ))
    )
),
troponin_events AS (
  SELECT l.hadm_id,
         l.charttime,
         l.valuenum
  FROM ischemic_admissions ia
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = ia.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON l.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%troponin t%' OR LOWER(di.label) LIKE '%troponin-t%')
),
first_troponin AS (
  SELECT hadm_id, valuenum
  FROM (
    SELECT hadm_id, charttime, valuenum,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM troponin_events
  )
  WHERE rn = 1
),
filtered AS (
  SELECT valuenum
  FROM first_troponin
  WHERE valuenum > 0.014
)
SELECT
  quantiles[OFFSET(2)] AS median_troponin_ng_per_mL,
  quantiles[OFFSET(1)] AS q1_troponin_ng_per_mL,
  quantiles[OFFSET(3)] AS q3_troponin_ng_per_mL,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_troponin_ng_per_mL
FROM (
  SELECT APPROX_QUANTILES(valuenum, 4) AS quantiles
  FROM filtered
);