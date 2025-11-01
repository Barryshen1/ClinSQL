WITH qualifying_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age >= 90
    AND di.seq_num = 1
    AND LOWER(d.long_title) LIKE '%chest pain%'
),
initial_troponin_candidates AS (
  SELECT qa.subject_id, qa.hadm_id, l.charttime, l.valuenum
  FROM qualifying_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON qa.subject_id = l.subject_id AND qa.hadm_id = l.hadm_id
  WHERE l.itemid = 33516
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
),
first_troponin AS (
  SELECT subject_id, hadm_id, valuenum
  FROM (
    SELECT subject_id, hadm_id, valuenum,
           ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM initial_troponin_candidates
  )
  WHERE rn = 1
    AND valuenum > 0.4  -- Initially elevated
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS p75,
  MIN(valuenum) AS min_val,
  MAX(valuenum) AS max_val
FROM first_troponin;