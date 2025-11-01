WITH chest_pain_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    dd.icd_code IN ('786.50', 'R07.4') -- ICD-9 and ICD-10 for chest pain
),

troponin_first AS (
  SELECT
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin i%'
    AND l.valuenum IS NOT NULL
),

initial_troponin AS (
  SELECT
    t.hadm_id,
    t.valuenum AS troponin_value
  FROM
    troponin_first t
  WHERE
    t.rn = 1
),

filtered_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    t.troponin_value
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    chest_pain_admissions c
    ON p.subject_id = c.subject_id
  JOIN
    initial_troponin t
    ON c.hadm_id = t.hadm_id
  WHERE
    p.anchor_age BETWEEN 90 AND 100
    AND p.gender = 'M'
)

SELECT
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(75)] AS p75,
  MAX(troponin_value) - MIN(troponin_value) AS `range`
FROM
  filtered_patients;