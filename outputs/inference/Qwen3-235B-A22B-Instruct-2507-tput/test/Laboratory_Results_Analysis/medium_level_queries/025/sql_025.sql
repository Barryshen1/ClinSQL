WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 58 AND 68
),

admissions_with_condition AS (
  SELECT DISTINCT
    pa.hadm_id
  FROM
    patient_admissions pa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON
    pa.hadm_id = di.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%chest pain%'
    OR LOWER(d.long_title) LIKE '%myocardial infarction%'
    OR LOWER(d.long_title) LIKE '%acute mi%'
),

trop_t AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
  ON
    le.itemid = dl.itemid
  WHERE
    LOWER(dl.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
),

first_trop_t AS (
  SELECT
    hadm_id,
    MIN(charttime) AS first_trop_t_time
  FROM
    trop_t
  GROUP BY
    hadm_id
),

first_trop_t_value AS (
  SELECT
    t.hadm_id,
    t.valuenum AS first_value
  FROM
    trop_t t
  INNER JOIN
    first_trop_t f
  ON
    t.hadm_id = f.hadm_id
    AND t.charttime = f.first_trop_t_time
),

qualified_admissions AS (
  SELECT
    f.hadm_id
  FROM
    first_trop_t_value f
  INNER JOIN
    admissions_with_condition a
  ON
    f.hadm_id = a.hadm_id
  WHERE
    f.first_value > 0.01
)

-- Final: Get all Troponin T values for qualified admissions and compute stats
SELECT
  AVG(le.valuenum) AS mean_troponin_t,
  STDDEV(le.valuenum) AS std_troponin_t,
  MIN(le.valuenum) AS min_troponin_t,
  MAX(le.valuenum) AS max_troponin_t
FROM
  `physionet-data.mimiciv_3_1_hosp`.labevents le
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
ON
  le.itemid = dl.itemid
INNER JOIN
  qualified_admissions q
ON
  le.hadm_id = q.hadm_id
WHERE
  LOWER(dl.label) = 'troponin t'
  AND le.valuenum IS NOT NULL;