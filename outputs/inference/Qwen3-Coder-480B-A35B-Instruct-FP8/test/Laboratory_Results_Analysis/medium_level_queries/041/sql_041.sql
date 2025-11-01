WITH troponin_first AS (
  SELECT
    l.hadm_id,
    l.valuenum
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems AS d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
    AND LOWER(d.fluid) = 'blood'
    AND l.valueuom = 'ng/mL'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0.014
    AND l.charttime = (
      SELECT MIN(charttime)
      FROM physionet-data.mimiciv_3_1_hosp.labevents AS l2
      WHERE l2.hadm_id = l.hadm_id
        AND l2.itemid = l.itemid
    )
),
acs_admissions AS (
  SELECT DISTINCT
    di.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS di
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%acute coronary%'
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS iqr
FROM
  troponin_first AS t
INNER JOIN
  acs_admissions AS a
  ON t.hadm_id = a.hadm_id
INNER JOIN
  physionet-data.mimiciv_3_1_hosp.admissions AS adm
  ON t.hadm_id = adm.hadm_id
INNER JOIN
  physionet-data.mimiciv_3_1_hosp.patients AS p
  ON adm.subject_id = p.subject_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 43 AND 53;