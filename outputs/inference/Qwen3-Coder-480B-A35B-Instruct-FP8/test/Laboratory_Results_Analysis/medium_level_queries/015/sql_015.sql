WITH admissions_with_age AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    p.gender,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 88 AND 98
),
acs_admissions AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%acute coronary%'
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
  ON
    l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'troponin t'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0.01
    AND LOWER(l.valueuom) = 'ng/ml'
)
SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_troponin,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS q1_troponin,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS q3_troponin,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr_troponin
FROM
  troponin_first t
JOIN
  admissions_with_age a
ON
  t.hadm_id = a.hadm_id
JOIN
  acs_admissions acs
ON
  t.hadm_id = acs.hadm_id
WHERE
  t.rn = 1;