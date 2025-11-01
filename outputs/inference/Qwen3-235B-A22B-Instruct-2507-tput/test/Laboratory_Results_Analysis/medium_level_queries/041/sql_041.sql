WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
),

acs_admissions AS (
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
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
),

troponin_labevents AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
  ON
    le.itemid = dl.itemid
  WHERE
    LOWER(dl.label) = 'troponein t, high sensitivity'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
),

first_troponin AS (
  SELECT
    hadm_id,
    valuenum
  FROM
    troponin_labevents
  WHERE
    rn = 1
)

SELECT
  APPROX_QUANTILES(t.valuenum, 1000)[OFFSET(500)] AS median_troponin_ng_ml,
  APPROX_QUANTILES(t.valuenum, 1000)[OFFSET(250)] AS q1_troponin_ng_ml,
  APPROX_QUANTILES(t.valuenum, 1000)[OFFSET(750)] AS q3_troponin_ng_ml
FROM
  first_troponin t
INNER JOIN
  acs_admissions a
ON
  t.hadm_id = a.hadm_id
WHERE
  t.valuenum > 0.014;