WITH initial_troponin AS (
  SELECT
    l.hadm_id,
    l.valuenum,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0.01
),
filtered_admissions AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND (
      LOWER(di.long_title) LIKE '%chest pain%'
      OR LOWER(di.long_title) LIKE '%acute myocardial infarction%'
    )
)
SELECT
  APPROX_QUANTILES(it.valuenum, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(it.valuenum, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(it.valuenum, 4)[OFFSET(3)] AS p75,
  MIN(it.valuenum) AS min,
  MAX(it.valuenum) AS max
FROM
  initial_troponin it
INNER JOIN
  filtered_admissions fa
  ON it.hadm_id = fa.hadm_id
WHERE
  it.rn = 1;