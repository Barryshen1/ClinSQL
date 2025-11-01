WITH troponin_labs AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE le.valuenum IS NOT NULL
    AND LOWER(di.label) LIKE '%troponin t%'
    AND LOWER(di.fluid) = 'blood'
),
uln_calc AS (
  SELECT
    APPROX_QUANTILES(valuenum, 100)[OFFSET(99)] AS troponin_t_uln
  FROM troponin_labs
),
first_trop_per_patient AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    tl.valuenum,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY tl.charttime) AS rn
  FROM troponin_labs tl
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON tl.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
)
SELECT
  COUNT(*) AS cohort_size,
  u.troponin_t_uln AS uln_99th_percentile,
  quantiles[OFFSET(25)] AS p25,
  quantiles[OFFSET(50)] AS median,
  quantiles[OFFSET(75)] AS p75,
  MIN(ft.valuenum) AS min_value,
  MAX(ft.valuenum) AS max_value
FROM (
  SELECT
    ft.*,
    APPROX_QUANTILES(ft.valuenum, 100) AS quantiles
  FROM first_trop_per_patient ft
  WHERE ft.rn = 1
) ft
CROSS JOIN uln_calc u
WHERE ft.valuenum > u.troponin_t_uln
GROUP BY u.troponin_t_uln, quantiles;