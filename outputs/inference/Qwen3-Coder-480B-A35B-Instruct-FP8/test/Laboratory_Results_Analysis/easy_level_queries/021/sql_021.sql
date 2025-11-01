WITH pneumonia_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
glucose_at_discharge AS (
  SELECT
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime DESC) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  JOIN
    pneumonia_admissions pa
    ON l.hadm_id = pa.hadm_id
  WHERE
    LOWER(d.label) = 'glucose'
    AND d.fluid = 'Blood'
    AND l.valuenum IS NOT NULL
    AND l.charttime <= pa.dischtime
)
SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS glucose_75th_percentile_at_discharge
FROM
  glucose_at_discharge
WHERE
  rn = 1;