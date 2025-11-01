WITH troponin_t_first AS (
  SELECT
    l.hadm_id,
    l.valuenum AS troponin_value
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems AS d
    ON l.itemid = d.itemid
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions AS a
    ON l.hadm_id = a.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients AS p
    ON a.subject_id = p.subject_id
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
    AND d.fluid = 'Blood'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0.01
    AND l.charttime IS NOT NULL
    AND l.charttime >= a.admittime
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) = 1
)

SELECT
  COUNT(*) AS n,
  AVG(troponin_value) AS mean,
  STDDEV(troponin_value) AS stddev,
  MIN(troponin_value) AS min,
  MAX(troponin_value) AS max,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(75)] AS percentile_75
FROM
  troponin_t_first;