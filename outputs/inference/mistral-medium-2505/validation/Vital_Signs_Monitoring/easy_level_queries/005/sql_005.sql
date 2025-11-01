WITH female_patients_59_69 AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 59 AND 69
),

systolic_bp_measurements AS (
  SELECT
    ce.valuenum AS systolic_bp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    female_patients_59_69 fp ON ce.subject_id = fp.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    di.label = 'Systolic BP'
    AND ce.valuenum BETWEEN 50 AND 300  -- Exclude extreme values
)

SELECT
  PERCENTILE_CONT(systolic_bp, 0.75) OVER() AS p75_systolic_bp
FROM
  systolic_bp_measurements
LIMIT 1;