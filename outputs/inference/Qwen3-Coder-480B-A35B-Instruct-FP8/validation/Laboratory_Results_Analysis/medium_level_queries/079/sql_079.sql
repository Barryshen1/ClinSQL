WITH troponin_first AS (
  SELECT
    l.hadm_id,
    MIN(l.valuenum) AS first_troponin
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems AS d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'troponin t'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0.01
  GROUP BY
    l.hadm_id
),
primary_diagnosis AS (
  SELECT
    di.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS di
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    di.seq_num = 1
    AND (
      LOWER(d.long_title) LIKE '%chest pain%'
      OR LOWER(d.long_title) LIKE '%myocardial infarction%'
    )
)
SELECT
  APPROX_QUANTILES(first_troponin, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(first_troponin, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(first_troponin, 100)[OFFSET(75)] AS p75,
  MIN(first_troponin) AS min_val,
  MAX(first_troponin) AS max_val
FROM
  troponin_first t
INNER JOIN
  primary_diagnosis pd
  ON t.hadm_id = pd.hadm_id
INNER JOIN
  physionet-data.mimiciv_3_1_hosp.admissions a
  ON t.hadm_id = a.hadm_id
INNER JOIN
  physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 82 AND 92;