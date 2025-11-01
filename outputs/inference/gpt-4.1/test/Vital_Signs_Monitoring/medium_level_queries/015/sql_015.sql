WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND (
      a.admission_location LIKE '%EMERGENCY%'
      OR a.admission_type = 'EMERGENCY'
    )
)

, sbp_per_stay AS (
  SELECT
    c.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM
    cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (220179, 220050) -- NIBP Systolic, Arterial Systolic
    AND ce.valuenum IS NOT NULL
  GROUP BY
    c.stay_id
)

SELECT
  APPROX_QUANTILES(max_sbp, 4)[OFFSET(3)] AS sbp_75th_percentile
FROM
  sbp_per_stay
;