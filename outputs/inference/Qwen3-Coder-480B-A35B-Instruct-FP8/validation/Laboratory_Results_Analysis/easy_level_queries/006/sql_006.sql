WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
  ON
    p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.anchor_age = 50
    AND p.gender = 'F'
    AND LOWER(dd.long_title) LIKE '%copd%'
),
sodium_nadir AS (
  SELECT
    l.hadm_id,
    MIN(l.valuenum) AS nadir_sodium
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
  ON
    l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'sodium'
    AND LOWER(d.fluid) = 'blood'
    AND l.valuenum IS NOT NULL
    AND l.hadm_id IN (SELECT hadm_id FROM cohort)
  GROUP BY
    l.hadm_id
)
SELECT
  STDDEV(nadir_sodium) AS stddev_nadir_sodium
FROM
  sodium_nadir;