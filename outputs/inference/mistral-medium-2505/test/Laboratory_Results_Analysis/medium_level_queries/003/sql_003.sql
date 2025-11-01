WITH
-- Get female patients aged 36-46
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 36 AND 46
),

-- Get admissions with ischemic heart disease (IHD) diagnoses
ihd_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM female_patients)
    AND (
      d.icd_code LIKE 'I20.%'
      OR d.icd_code LIKE 'I21.%'
      OR d.icd_code LIKE 'I22.%'
      OR d.icd_code LIKE 'I23.%'
      OR d.icd_code LIKE 'I24.%'
      OR d.icd_code LIKE 'I25.%'
    )
),

-- Get initial high-sensitivity Troponin T > ULN (0.014)
initial_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum AS troponin_value
  FROM (
    SELECT
      subject_id,
      hadm_id,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
      itemid = 50930  -- High-sensitivity Troponin T
      AND hadm_id IN (SELECT hadm_id FROM ihd_admissions)
  ) le
  WHERE
    le.rn = 1  -- First measurement per admission
    AND le.valuenum > 0.014  -- ULN threshold
)

-- Calculate percentiles and min/max
SELECT
  APPROX_QUANTILES(initial_troponin.troponin_value, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(initial_troponin.troponin_value, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(initial_troponin.troponin_value, 4)[OFFSET(3)] AS p75,
  MIN(initial_troponin.troponin_value) AS min_value,
  MAX(initial_troponin.troponin_value) AS max_value
FROM
  initial_troponin
LIMIT 1;