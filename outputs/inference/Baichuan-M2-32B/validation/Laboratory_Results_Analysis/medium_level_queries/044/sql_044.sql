WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    p.anchor_year,
    p.anchor_age,
    TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 54 AND 64
),
troponin_t AS (
  SELECT
    e.hadm_id,
    e.subject_id,
    e.labevent_id,
    e.charttime,
    e.valuenum,
    e.valueuom,
    ROW_NUMBER() OVER (
      PARTITION BY e.hadm_id
      ORDER BY e.charttime, e.labevent_id
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON e.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin t%'   -- Fixed: Use label instead of loinc_code
    AND e.valueuom IN ('ng/mL', 'ng/ml')
    AND e.valuenum IS NOT NULL
),
first_troponin_t AS (
  SELECT
    hadm_id,
    subject_id,
    valuenum
  FROM troponin_t
  WHERE rn = 1
)
SELECT
  COUNT(*) AS n,
  AVG(valuenum) AS mean,
  STDDEV(valuenum) AS sd,
  MIN(valuenum) AS min,
  MAX(valuenum) AS max,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75
FROM eligible_admissions e
INNER JOIN first_troponin_t f
  ON e.hadm_id = f.hadm_id
WHERE f.valuenum > 0.01;