WITH qualifying_labs AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
  ON 
    le.itemid = dli.itemid
  WHERE 
    LOWER(dli.label) LIKE '%troponin-t%'
    AND le.valuenum > 0.01
    AND le.valueuom = 'ng/mL'
    AND le.valuenum IS NOT NULL
),
first_troponin AS (
  SELECT 
    ql.hadm_id,
    MAX(ql.valuenum) AS initial_troponin_t  -- Take any valid value if multiple at exact min time
  FROM (
    SELECT 
      hadm_id,
      MIN(charttime) AS min_charttime
    FROM 
      qualifying_labs
    GROUP BY 
      hadm_id
  ) min_times
  INNER JOIN 
    qualifying_labs ql
  ON 
    min_times.hadm_id = ql.hadm_id 
    AND min_times.min_charttime = ql.charttime
  GROUP BY 
    ql.hadm_id
)
SELECT 
  COUNT(*) AS n,
  ROUND(AVG(initial_troponin_t), 4) AS mean,
  ROUND(STDDEV(initial_troponin_t), 4) AS sd,
  ROUND(MIN(initial_troponin_t), 4) AS min,
  ROUND(MAX(initial_troponin_t), 4) AS max,
  ROUND(APPROX_QUANTILES(initial_troponin_t, 4)[OFFSET(2)], 4) AS median,
  ROUND(APPROX_QUANTILES(initial_troponin_t, 4)[OFFSET(1)], 4) AS p25,
  ROUND(APPROX_QUANTILES(initial_troponin_t, 4)[OFFSET(3)], 4) AS p75
FROM 
  first_troponin ft
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
ON 
  ft.hadm_id = adm.hadm_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` pat
ON 
  adm.subject_id = pat.subject_id
WHERE 
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 54 AND 64;