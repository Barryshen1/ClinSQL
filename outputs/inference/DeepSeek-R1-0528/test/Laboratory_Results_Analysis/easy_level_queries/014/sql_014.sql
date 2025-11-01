WITH cohort AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) = 45
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('5780', '5781', '5789'))
      OR
      (diag.icd_version = 10 AND diag.icd_code IN ('K920', 'K921', 'K922', 'K250', 'K252', 'K254', 'K256', 'K260', 'K262', 'K264', 'K266', 'K270', 'K272', 'K274', 'K276', 'K280', 'K282', 'K284', 'K286'))
    )
),

lab_hemo AS (
  SELECT
    lab.hadm_id,
    lab.charttime,
    lab.valuenum AS hemoglobin
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  INNER JOIN cohort
    ON lab.hadm_id = cohort.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON lab.itemid = dlab.itemid
  WHERE
    (dlab.label LIKE '%hemoglobin%' OR dlab.label LIKE 'Hgb%')
    AND dlab.fluid = 'Blood'
    AND lab.valuenum IS NOT NULL
    AND lab.valueuom = 'g/dL'
    AND DATE(lab.charttime) = DATE(cohort.dischtime)
),

last_hemo AS (
  SELECT
    hadm_id,
    hemoglobin,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime DESC) AS rn
  FROM lab_hemo
)

SELECT
  APPROX_QUANTILES(hemoglobin, 100)[OFFSET(75)] AS percentile_75
FROM last_hemo
WHERE rn = 1;