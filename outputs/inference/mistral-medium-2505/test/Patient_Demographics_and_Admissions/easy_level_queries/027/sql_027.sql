WITH first_admissions AS (
  -- Get the first admission for each patient
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS length_of_stay_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN (
    -- Find the first hadm_id for each subject_id
    SELECT
      subject_id,
      MIN(hadm_id) AS first_hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY
      subject_id
  ) first_adm ON a.subject_id = first_adm.subject_id AND a.hadm_id = first_adm.first_hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
)

SELECT
  PERCENTILE_CONT(length_of_stay_days, 0.25) OVER() AS q1,
  PERCENTILE_CONT(length_of_stay_days, 0.5) OVER() AS median,
  PERCENTILE_CONT(length_of_stay_days, 0.75) OVER() AS q3,
  PERCENTILE_CONT(length_of_stay_days, 0.75) OVER() - PERCENTILE_CONT(length_of_stay_days, 0.25) OVER() AS iqr
FROM
  first_admissions
LIMIT 1;