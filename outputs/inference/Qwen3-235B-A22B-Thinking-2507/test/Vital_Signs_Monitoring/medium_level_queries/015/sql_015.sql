WITH eligible_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_type = 'EMERGENCY'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 59 AND 69
),
eligible_stays AS (
  SELECT
    ea.subject_id,
    ea.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    eligible_admissions ea
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays i
    ON ea.hadm_id = i.hadm_id
),
sbp_measurements AS (
  SELECT
    es.stay_id,
    ce.valuenum AS sbp
  FROM
    eligible_stays es
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON es.stay_id = ce.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  WHERE
    ce.charttime >= es.intime
    AND ce.charttime <= es.outtime
    AND di.label IN ('Arterial Blood Pressure systolic', 'Non Invasive Blood Pressure systolic')
    AND ce.valuenum IS NOT NULL
),
max_sbp_per_stay AS (
  SELECT
    stay_id,
    MAX(sbp) AS max_sbp
  FROM
    sbp_measurements
  GROUP BY
    stay_id
)
SELECT
  APPROX_QUANTILES(max_sbp, 1000)[OFFSET(750)] AS sbp_75th_percentile
FROM
  max_sbp_per_stay;