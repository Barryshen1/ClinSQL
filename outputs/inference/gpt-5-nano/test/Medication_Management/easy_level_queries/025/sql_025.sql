WITH filtered_prescriptions AS (
  SELECT
    pres.subject_id,
    pres.hadm_id,
    pres.starttime,
    pres.stoptime,
    pres.drug,
    adm.admittime,
    pat.anchor_age,
    pat.anchor_year,
    pat.gender
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pres.subject_id = adm.subject_id
   AND pres.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pres.subject_id = pat.subject_id
  WHERE LOWER(pres.drug) LIKE '%amiodarone%'
    AND pat.gender = 'M'
    -- Age at admission using anchor_age and anchor_year
    AND CAST(pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS INT64) BETWEEN 62 AND 72
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND pres.stoptime >= pres.starttime
),
durations AS (
  SELECT
    DATE_DIFF(DATE(pst.stoptime), DATE(pst.starttime), DAY) AS duration_days
  FROM filtered_prescriptions AS pst
  WHERE DATE_DIFF(DATE(pst.stoptime), DATE(pst.starttime), DAY) IS NOT NULL
    AND DATE_DIFF(DATE(pst.stoptime), DATE(pst.starttime), DAY) >= 0
)
SELECT
  SAFE_CAST(quantiles[OFFSET(1)] AS FLOAT64) AS q1_days,
  SAFE_CAST(quantiles[OFFSET(3)] AS FLOAT64) AS q3_days,
  SAFE_CAST(quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS FLOAT64) AS iqr_days
FROM (
  SELECT APPROX_QUANTILES(duration_days, 4) AS quantiles
  FROM durations
) AS q;