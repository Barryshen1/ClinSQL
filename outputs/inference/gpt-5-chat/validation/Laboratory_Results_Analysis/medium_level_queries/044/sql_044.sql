WITH troponin_events AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
  ON
    le.itemid = dl.itemid
  WHERE
    LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
),
initial_troponin AS (
  SELECT
    te.subject_id,
    te.hadm_id,
    te.valuenum,
    ROW_NUMBER() OVER (PARTITION BY te.hadm_id ORDER BY te.charttime ASC) AS rn
  FROM
    troponin_events te
)
SELECT
  COUNT(*) AS n,
  AVG(valuenum) AS mean_tropT,
  STDDEV(valuenum) AS sd_tropT,
  MIN(valuenum) AS min_tropT,
  MAX(valuenum) AS max_tropT,
  APPROX_QUANTILES(valuenum, 100)[50] AS median_tropT,
  APPROX_QUANTILES(valuenum, 100)[25] AS q1_tropT,
  APPROX_QUANTILES(valuenum, 100)[75] AS q3_tropT
FROM
  initial_troponin it
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
ON
  it.hadm_id = adm.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
ON
  it.subject_id = pat.subject_id
WHERE
  it.rn = 1
  AND pat.gender = 'M'
  AND pat.anchor_age BETWEEN 54 AND 64
  AND it.valuenum > 0.01;