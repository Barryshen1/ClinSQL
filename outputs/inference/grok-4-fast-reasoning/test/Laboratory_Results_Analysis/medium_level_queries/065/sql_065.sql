WITH qualifying_adms AS (
  SELECT DISTINCT 
    p.subject_id, 
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON d.subject_id = p.subject_id
  WHERE ((d.icd_version = 9 AND d.icd_code LIKE '410%')
     OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%'))
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
),
first_trop AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN qualifying_adms qa 
    ON l.hadm_id = qa.hadm_id
  WHERE l.itemid = 50920
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
),
initial_trops AS (
  SELECT valuenum
  FROM first_trop
  WHERE rn = 1
    AND valuenum > 0.04
),
quantiles_cte AS (
  SELECT 
    APPROX_QUANTILES(valuenum, 4) AS qs
  FROM initial_trops
)
SELECT 
  qs[OFFSET(1)] AS q1,
  qs[OFFSET(2)] AS median_troponin_t,
  qs[OFFSET(3)] AS q3,
  qs[OFFSET(3)] - qs[OFFSET(1)] AS iqr
FROM quantiles_cte;