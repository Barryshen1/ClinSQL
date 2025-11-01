WITH first_admit AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS LOS_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime ASC) = 1
)
SELECT
  (quad)[OFFSET(1)] AS q1_25,
  (quad)[OFFSET(3)] AS q3_75,
  ((quad)[OFFSET(3)] - (quad)[OFFSET(1)]) AS iqr_25_75
FROM (
  SELECT APPROX_QUANTILES(LOS_days, 4) AS quad
  FROM first_admit
  WHERE UPPER(gender) IN ('F','FEMALE')
    AND age_at_admit BETWEEN 77 AND 87
    AND LOS_days IS NOT NULL
);