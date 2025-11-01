WITH troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin i%'
     OR LOWER(label) LIKE '%troponin t%'
),
acs_codes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code = '411.1'))
     OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code = 'I20.0'))
),
peak_troponin_per_admission AS (
  SELECT
    le.hadm_id,
    MAX(le.valuenum) AS peak_troponin
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN troponin_items ti ON le.itemid = ti.itemid
  INNER JOIN acs_codes ac ON le.hadm_id = ac.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON le.subject_id = p.subject_id
  WHERE le.valuenum IS NOT NULL
    AND p.gender = 'M'
  GROUP BY le.hadm_id
)
SELECT
  APPROX_QUANTILES(peak_troponin, 1000)[OFFSET(750)] AS troponin_75th_percentile
FROM peak_troponin_per_admission;