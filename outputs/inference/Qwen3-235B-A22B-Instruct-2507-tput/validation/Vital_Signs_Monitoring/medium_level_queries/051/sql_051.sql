WITH max_hr_per_stay AS (
  SELECT
    ce.stay_id,
    MAX(ce.valuenum) AS max_hr
  FROM
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients p
    ON icu.subject_id = p.subject_id
  WHERE
    LOWER(di.label) = 'heart rate'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.stay_id
)
SELECT
  APPROX_QUANTILES(max_hr, 1000)[OFFSET(250)] AS q1,
  APPROX_QUANTILES(max_hr, 1000)[OFFSET(750)] AS q3,
  APPROX_QUANTILES(max_hr, 1000)[OFFSET(750)] - APPROX_QUANTILES(max_hr, 1000)[OFFSET(250)] AS iqr
FROM
  max_hr_per_stay;