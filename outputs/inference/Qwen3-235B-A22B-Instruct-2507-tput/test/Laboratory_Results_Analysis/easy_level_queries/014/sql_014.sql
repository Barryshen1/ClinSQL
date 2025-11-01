WITH gi_bleeding_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%gastrointest%hemorr%'
     OR LOWER(long_title) LIKE '%hematem%'
     OR LOWER(long_title) LIKE '%melena%'
     OR LOWER(long_title) LIKE '%bleed%stomach%'
     OR LOWER(long_title) LIKE '%bleed%intestine%'
),
eligible_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.anchor_age = 45
    AND p.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id = a.hadm_id
        AND di.icd_version = 10
        AND di.icd_code IN (SELECT icd_code FROM gi_bleeding_codes WHERE icd_version = 10)
    )
),
hemo_lab AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%hemo%'
    AND LOWER(label) LIKE '%globin%'
),
discharge_day_hemo AS (
  SELECT
    la.hadm_id,
    le.valuenum AS hemoglobin
  FROM eligible_admissions la
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON la.hadm_id = le.hadm_id
  CROSS JOIN hemo_lab hl
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON la.hadm_id = a.hadm_id
  WHERE le.itemid = hl.itemid
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND DATE(le.charttime) = DATE(a.dischtime)
)
SELECT
  APPROX_QUANTILES(hemoglobin, 100)[OFFSET(75)] AS hemoglobin_75th_percentile
FROM discharge_day_hemo;