WITH cohort AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag AS mortality
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
)
SELECT
  -- Approximate quartiles: index 0 = min, 1 = Q1, 2 = median, 3 = Q3, 4 = max
  qs[3] - qs[1] AS iqr_mortality
FROM (
  SELECT
    APPROX_QUANTILES(mortality, 4) AS qs
  FROM cohort
);