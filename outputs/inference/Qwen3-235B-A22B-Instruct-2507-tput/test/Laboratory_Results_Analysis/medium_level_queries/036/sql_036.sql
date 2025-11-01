WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 77 AND 87
),

ami_admissions AS (
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
    (d.icd_version = 9 AND d.icd_code LIKE '410%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
),

hstnt_observations AS (
  SELECT
    l.hadm_id,
    l.valuenum,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp`.labevents l
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_labitems d
  ON
    l.itemid = d.itemid
  WHERE
    (LOWER(d.label) LIKE '%trop%high%sens%' 
     OR LOWER(d.label) LIKE '%troponin high sensitive%'
     OR d.loinc_code = '48990-0')
    AND l.valuenum IS NOT NULL
),

first_hstnt AS (
  SELECT
    ha.hadm_id,
    ho.valuenum
  FROM
    ami_admissions ha
  INNER JOIN
    hstnt_observations ho
  ON
    ha.hadm_id = ho.hadm_id
  WHERE
    ho.rn = 1
),

classified AS (
  SELECT
    CASE
      WHEN valuenum <= 14 THEN 'normal'
      WHEN valuenum BETWEEN 15 AND 59 THEN 'borderline'
      WHEN valuenum >= 60 THEN 'myocardial injury'
      ELSE 'unknown'
    END AS category
  FROM
    first_hstnt
)

SELECT
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM
  classified
GROUP BY
  category
ORDER BY
  category;