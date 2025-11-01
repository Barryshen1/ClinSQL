WITH troponin_first AS (
  SELECT
    hadm_id,
    valuenum AS first_trop_value
  FROM (
    SELECT
      l.hadm_id,
      l.valuenum,
      ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
    FROM
      physionet-data.mimiciv_3_1_hosp.labevents l
    INNER JOIN
      physionet-data.mimiciv_3_1_hosp.d_labitems d
      ON l.itemid = d.itemid
    WHERE
      LOWER(d.label) = 'troponin t'
      AND l.valuenum IS NOT NULL
  ) ranked
  WHERE rn = 1
  AND valuenum > 0.014
),
eligible_admissions AS (
  SELECT
    a.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
  INTERSECT DISTINCT
  SELECT
    di.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    (d.icd_version = 9 AND d.icd_code LIKE '414%')
    OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I2[0-5]'))
)
SELECT
  APPROX_QUANTILES(t.first_trop_value, 4)[OFFSET(2)] AS median_trop_t,
  APPROX_QUANTILES(t.first_trop_value, 4)[OFFSET(1)] AS q1_trop_t,
  APPROX_QUANTILES(t.first_trop_value, 4)[OFFSET(3)] AS q3_trop_t,
  APPROX_QUANTILES(t.first_trop_value, 4)[OFFSET(3)] - APPROX_QUANTILES(t.first_trop_value, 4)[OFFSET(1)] AS iqr_trop_t
FROM
  troponin_first t
INNER JOIN
  eligible_admissions e
  ON t.hadm_id = e.hadm_id;