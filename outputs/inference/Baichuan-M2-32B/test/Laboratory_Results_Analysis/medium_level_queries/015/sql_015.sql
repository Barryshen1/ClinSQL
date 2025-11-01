WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 88 AND 98
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code IN ('I21', 'I20.0', 'I20.1')  -- ICD-10 codes for ACS
    )
),
first_troponin AS (
  SELECT 
    e.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY e.hadm_id ORDER BY l.charttime) AS rn
  FROM eligible_admissions e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON e.hadm_id = l.hadm_id
  WHERE 
    l.itemid = 50809  -- Troponin T quantitative (LOINC 2160-0)
    AND l.charttime BETWEEN e.admittime AND e.dischtime
),
troponin_values AS (
  SELECT 
    hadm_id,
    valuenum
  FROM first_troponin
  WHERE rn = 1
    AND valuenum > 0.01  -- Only admissions with first Troponin T >0.01 ng/mL
)
SELECT
  quartiles[OFFSET(1)] AS q1,
  quartiles[OFFSET(2)] AS median,
  quartiles[OFFSET(3)] AS q3
FROM (
  SELECT
    APPROX_QUANTILES(valuenum, 4) AS quartiles
  FROM troponin_values
);