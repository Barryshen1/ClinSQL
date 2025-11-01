WITH cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
),
rr_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.label = 'Respiratory Rate'
    AND ce.valuenum IS NOT NULL
),
first_rr AS (
  SELECT
    c.hadm_id,
    r.valuenum,
    ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY r.charttime ASC) AS rn
  FROM cohort c
  JOIN rr_events r
    ON c.subject_id = r.subject_id
   AND c.hadm_id = r.hadm_id
  WHERE r.charttime >= c.admittime
)
SELECT
  STDDEV(valuenum) AS sd_first_rr
FROM first_rr
WHERE rn = 1;