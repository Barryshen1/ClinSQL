WITH male_49_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 49
),
hf_admissions AS (
  SELECT DISTINCT
    m.subject_id,
    m.hadm_id
  FROM
    male_49_admissions AS m
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON m.subject_id = d.subject_id
     AND m.hadm_id    = d.hadm_id
  WHERE
    (d.icd_version = 9  AND d.icd_code LIKE '428%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
),
nadir_hemoglobin AS (
  SELECT
    l.hadm_id,
    MIN(l.valuenum) AS nadir_hgb
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents`   AS l
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
      ON l.itemid = li.itemid
    JOIN hf_admissions AS hf
      ON l.hadm_id = hf.hadm_id
  WHERE
    li.loinc_code = '718-7'
    AND l.valuenum IS NOT NULL
  GROUP BY
    l.hadm_id
)
SELECT
  APPROX_QUANTILES(nadir_hgb, 100)[OFFSET(75)] AS pct75_nadir_hemoglobin
FROM
  nadir_hemoglobin;