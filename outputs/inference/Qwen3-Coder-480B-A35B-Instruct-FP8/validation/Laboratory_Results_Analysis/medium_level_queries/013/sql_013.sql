WITH age_filtered_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 50 AND 60
),

ami_or_chest_pain_admissions AS (
  SELECT DISTINCT
    hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    (dd.icd_version = 9 AND (
      dd.icd_code LIKE '410%' OR
      dd.icd_code = '786.59'
    ))
    OR
    (dd.icd_version = 10 AND (
      dd.icd_code LIKE 'I21%' OR
      dd.icd_code LIKE 'I22%' OR
      dd.icd_code = 'R07.9'
    ))
),

first_troponin AS (
  SELECT
    l.hadm_id,
    l.valuenum AS troponin_value
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
  ON
    l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) = 1
),

filtered_admissions AS (
  SELECT
    afp.subject_id,
    afp.hadm_id,
    ft.troponin_value
  FROM
    age_filtered_patients afp
  JOIN
    ami_or_chest_pain_admissions ami
  ON
    afp.hadm_id = ami.hadm_id
  JOIN
    first_troponin ft
  ON
    afp.hadm_id = ft.hadm_id
  WHERE
    ft.troponin_value > 0.014
)

SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(troponin_value) AS mean_troponin,
  APPROX_QUANTILES(troponin_value, 2)[OFFSET(1)] AS median_troponin,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)] AS q1_troponin,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)] AS q3_troponin,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)] - APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)] AS iqr_troponin
FROM
  filtered_admissions;