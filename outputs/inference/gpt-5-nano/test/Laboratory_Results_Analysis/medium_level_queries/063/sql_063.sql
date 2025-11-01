WITH acs_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON d.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I2%')
      OR (d.icd_version = 9 AND (
           d.icd_code LIKE '410%' OR d.icd_code LIKE '411%' OR
           d.icd_code LIKE '413%' OR d.icd_code LIKE '414%'
         ))
    )
),
troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin i%'
),
initial_troponin AS (
  SELECT lv.hadm_id, lv.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS lv
  JOIN troponin_items AS ti ON lv.itemid = ti.itemid
  WHERE lv.hadm_id IN (SELECT hadm_id FROM acs_admissions)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY lv.hadm_id ORDER BY lv.charttime) = 1
  AND lv.valuenum > 0.04
),
initial_quant AS (
  SELECT APPROX_QUANTILES(valuenum, 100) AS q
  FROM initial_troponin
)
SELECT
  COUNT(*) AS n_admissions_with_elevated_troponin,
  AVG(valuenum) AS mean_troponin_i,
  (SELECT q[OFFSET(49)] FROM initial_quant) AS median_troponin_i,
  (SELECT q[OFFSET(24)]  FROM initial_quant) AS q25_troponin_i,
  (SELECT q[OFFSET(74)]  FROM initial_quant) AS q75_troponin_i,
  (SELECT q[OFFSET(74)] - q[OFFSET(24)] FROM initial_quant) AS iqr_troponin_i
FROM initial_troponin;