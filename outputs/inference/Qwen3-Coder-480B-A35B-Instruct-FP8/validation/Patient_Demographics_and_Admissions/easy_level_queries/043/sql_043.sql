WITH admissions_with_age AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission,
    p.gender
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
),
filtered_admissions AS (
  SELECT
    hadm_id,
    hospital_expire_flag AS mortality
  FROM
    admissions_with_age
  WHERE
    age_at_admission BETWEEN 51 AND 61
),
mortality_quantiles AS (
  SELECT
    APPROX_QUANTILES(mortality, 4) AS quantiles
  FROM
    filtered_admissions
)
SELECT
  quantiles[ORDINAL(3)] - quantiles[ORDINAL(1)] AS iqr_mortality
FROM
  mortality_quantiles;