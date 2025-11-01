WITH female_age AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 55 AND 65
),
ami_hadm AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN female_age fa
    ON fa.subject_id = di.subject_id
  WHERE (di.icd_version = 9 AND di.icd_code LIKE '410%')
     OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
),
hs_tnt_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND LOWER(label) LIKE '%sensitivity%'
),
first_hs_tnt AS (
  SELECT le.subject_id, le.hadm_id, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN hs_tnt_items it
    ON le.itemid = it.itemid
  JOIN ami_hadm ah
    ON le.subject_id = ah.subject_id AND le.hadm_id = ah.hadm_id
  WHERE le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
    AND le.valuenum > 0.01
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
),
quantiles AS (
  SELECT
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT hadm_id) AS admission_count,
    AVG(valuenum) AS mean_hs_tnt,
    APPROX_QUANTILES(valuenum, 100) AS qtls
  FROM first_hs_tnt
)
SELECT
  patient_count,
  admission_count,
  mean_hs_tnt,
  qtls[OFFSET(50)] AS median_hs_tnt,
  qtls[OFFSET(75)] - qtls[OFFSET(25)] AS iqr_hs_tnt
FROM quantiles;