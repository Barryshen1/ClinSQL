WITH patients_with_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 84 AND 94
),
acs_admissions AS (
  SELECT
    pw.age_at_admit,
    pw.hadm_id
  FROM
    patients_with_age pw
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON
    pw.hadm_id = di.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code = 'I200')
),
troponin_i_labevents AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
  ON
    le.itemid = dl.itemid
  WHERE
    LOWER(dl.label) = 'troponin i'
    AND le.valuenum IS NOT NULL
),
first_troponin_i AS (
  SELECT
    hadm_id,
    valuenum AS first_troponin_i
  FROM
    troponin_i_labevents
  WHERE
    rn = 1
),
acs_with_first_troponin AS (
  SELECT
    a.hadm_id,
    a.age_at_admit,
    f.first_troponin_i
  FROM
    acs_admissions a
  INNER JOIN
    first_troponin_i f
  ON
    a.hadm_id = f.hadm_id
  WHERE
    f.first_troponin_i > 0.04  -- Exceeds 99th percentile ULN
)
SELECT
  COUNT(*) AS count_patients,
  AVG(first_troponin_i) AS mean_troponin_i,
  APPROX_QUANTILES(first_troponin_i, 100)[OFFSET(50)] AS median_troponin_i,
  APPROX_QUANTILES(first_troponin_i, 100)[OFFSET(25)] AS q1_troponin_i,
  APPROX_QUANTILES(first_troponin_i, 100)[OFFSET(75)] AS q3_troponin_i
FROM
  acs_with_first_troponin;