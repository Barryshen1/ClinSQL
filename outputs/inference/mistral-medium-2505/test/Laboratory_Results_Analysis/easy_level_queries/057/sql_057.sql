WITH
-- Get the itemid for serum creatinine
serum_creatinine_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label = 'Creatinine' AND fluid = 'Serum'
),

-- Get male patients' hospital stays with nadir serum creatinine
nadir_creatinine AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    MIN(le.valuenum) AS nadir_creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON a.hadm_id = le.hadm_id
  JOIN serum_creatinine_item sci ON le.itemid = sci.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 62  -- Age range to account for rounding
    AND di.icd_code LIKE 'J18%'  -- Pneumonia diagnosis codes
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0  -- Exclude invalid values
  GROUP BY p.subject_id, a.hadm_id
),

-- Calculate the percentiles
percentiles AS (
  SELECT
    APPROX_QUANTILES(nadir_creatinine, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(nadir_creatinine, 100)[OFFSET(75)] AS q3
  FROM nadir_creatinine
)

-- Return the IQR
SELECT
  q1,
  q3,
  q3 - q1 AS iqr
FROM percentiles;