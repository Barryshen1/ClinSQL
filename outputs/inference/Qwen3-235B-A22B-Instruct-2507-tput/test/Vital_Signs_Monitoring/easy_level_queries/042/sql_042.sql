WITH patient_ages AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM i.intime) AS icu_year,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icu,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays i
  ON
    p.subject_id = i.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 63 AND 73
),
respiratory_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) = 'respiratory rate'
    AND linksto = 'chartevents'
),
patient_max_rr AS (
  SELECT
    ce.subject_id,
    MAX(ce.valuenum) AS max_rr
  FROM
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN
    respiratory_item ri
  ON
    ce.itemid = ri.itemid
  INNER JOIN
    patient_ages pa
  ON
    ce.subject_id = pa.subject_id
    AND ce.stay_id = pa.stay_id
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime >= pa.intime
    AND ce.charttime <= pa.outtime
  GROUP BY
    ce.subject_id
)
SELECT
  STDDEV(max_rr) AS sd_max_respiratory_rate
FROM
  patient_max_rr;