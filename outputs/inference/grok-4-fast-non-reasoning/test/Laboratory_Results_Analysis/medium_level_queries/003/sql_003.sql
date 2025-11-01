WITH ihd_admissions AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 36 AND 46
    AND d.icd_version = 'ICD-10-CM'
    AND d.icd_code LIKE 'I2[0-5]%'
),
first_troponin AS (
  SELECT 
    ia.subject_id,
    ia.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY ia.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM ihd_admissions ia
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON ia.subject_id = l.subject_id 
    AND ia.hadm_id = l.hadm_id
    AND l.itemid = CAST(535 AS INT64)  -- High-sensitivity Troponin T (itemid 535)
    AND l.valuenum > CAST(0 AS FLOAT64)  -- > ULN (approximate; adjust threshold if absolute ULN known, e.g., >14 for ng/L)
    AND l.charttime >= ia.admittime
    AND l.charttime <= ia.dischtime
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS p75,
  MIN(valuenum) AS min_val,
  MAX(valuenum) AS max_val
FROM first_troponin
WHERE rn = 1;