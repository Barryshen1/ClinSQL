WITH diastolic_bp AS (
  SELECT
    ie.stay_id,
    AVG(ce.valuenum) AS mean_diastolic_bp
  FROM
    physionet-data.mimiciv_3_1_icu.icustays ie
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON ie.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.chartevents ce
    ON ie.stay_id = ce.stay_id
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND LOWER(di.label) LIKE '%diastolic%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 200  -- reasonable upper bound for diastolic BP
    AND ie.first_careunit IN ('Stepdown Unit', 'IMC', 'Intermediate Care', 'SDU')
  GROUP BY
    ie.stay_id
),
iqr_calc AS (
  SELECT
    PERCENTILE_CONT(mean_diastolic_bp, 0.25) OVER () AS q1,
    PERCENTILE_CONT(mean_diastolic_bp, 0.75) OVER () AS q3
  FROM
    diastolic_bp
  WHERE
    mean_diastolic_bp IS NOT NULL
)
SELECT
  q3 - q1 AS iqr_mean_diastolic_bp
FROM
  iqr_calc
LIMIT 1;