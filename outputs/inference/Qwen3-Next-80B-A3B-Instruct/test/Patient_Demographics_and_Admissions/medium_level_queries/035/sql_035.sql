WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'death'
      WHEN a.discharge_location IN ('HOME', 'HOME WITH HOME CARE', 'HOME WITH SKILLED NURSING', 'HOME WITH HOSPICE') THEN 'home'
      WHEN a.discharge_location IN ('SNF', 'REHAB', 'LONG TERM CARE', 'OTHER FACILITY', 'FACILITY', 'PSYCH', 'ALTERNATE CARE') THEN 'facility'
      ELSE 'other'
    END AS discharge_outcome
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) >= 0
),
summary AS (
  SELECT
    discharge_outcome,
    APPROX_QUANTILES(los, 4)[OFFSET(2)] AS median_los,
    APPROX_QUANTILES(los, 4)[OFFSET(1)] AS q1_los,
    APPROX_QUANTILES(los, 4)[OFFSET(3)] AS q3_los,
    COUNTIF(los <= 14) * 100.0 / COUNT(*) AS percentile_rank_14day
  FROM
    cohort
  WHERE
    discharge_outcome IN ('home', 'facility', 'death')  -- exclude 'other'
  GROUP BY
    discharge_outcome
)
SELECT
  discharge_outcome,
  median_los,
  q1_los,
  q3_los,
  percentile_rank_14day
FROM
  summary
ORDER BY
  discharge_outcome;