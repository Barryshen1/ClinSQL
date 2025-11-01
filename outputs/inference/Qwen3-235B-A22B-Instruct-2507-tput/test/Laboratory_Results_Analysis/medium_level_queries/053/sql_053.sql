WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 68 AND 78
),

acs_admissions AS (
  SELECT DISTINCT
    pa.subject_id,
    pa.hadm_id,
    pa.age_at_admit
  FROM
    patient_admissions pa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON
    pa.hadm_id = di.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    d.icd_code LIKE 'I21%' OR d.icd_code = 'I20.0'  -- ACS: MI or Unstable Angina
),

troponin_i_first AS (
  SELECT
    l.hadm_id,
    l.valuenum AS first_trop_i
  FROM (
    SELECT
      l.hadm_id,
      l.valuenum,
      ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp`.labevents l
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp`.d_labitems d
    ON
      l.itemid = d.itemid
    WHERE
      LOWER(d.label) = 'troponin i'
      AND l.valuenum IS NOT NULL
  ) l
  WHERE
    l.rn = 1  -- First Troponin I measurement
)

SELECT
  COUNT(*) AS admission_count,
  COUNT(DISTINCT a.subject_id) AS patient_count,
  AVG(t.first_trop_i) AS mean_trop_i,
  STDDEV(t.first_trop_i) AS std_trop_i,
  MIN(t.first_trop_i) AS min_trop_i,
  MAX(t.first_trop_i) AS max_trop_i
FROM
  acs_admissions a
INNER JOIN
  troponin_i_first t
ON
  a.hadm_id = t.hadm_id
WHERE
  t.first_trop_i > 0.04;