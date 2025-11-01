WITH acs_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON d.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON d.subject_id = p.subject_id
  WHERE d.seq_num = 1
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '4111'))
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I20.0%' OR d.icd_code LIKE 'I21.%'))
    )
),
initial_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN acs_admissions aa
    ON le.hadm_id = aa.hadm_id
  WHERE le.itemid = 51488
    AND le.valuenum IS NOT NULL
    AND le.charttime >= aa.admittime
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS median_ng_ml,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS q1_ng_ml,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS q3_ng_ml,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS iqr_ng_ml
FROM initial_troponin
WHERE rn = 1
  AND valuenum > 0.014;