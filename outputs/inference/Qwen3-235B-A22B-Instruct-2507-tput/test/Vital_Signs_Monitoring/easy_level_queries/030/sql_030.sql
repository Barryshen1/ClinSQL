WITH patient_icu AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM i.intime) AS adm_year,
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age_at_icu_adm
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays i
  ON
    p.subject_id = i.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 38 AND 48
),

heart_rate_first AS (
  SELECT
    pi.stay_id,
    ce.valuenum AS first_hr
  FROM
    patient_icu pi
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  ON
    pi.stay_id = ce.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.d_items di
  ON
    ce.itemid = di.itemid
  WHERE
    LOWER(di.label) = 'heart rate'
    AND ce.charttime >= pi.intime
    AND ce.valuenum IS NOT NULL
    AND ce.charttime IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY pi.stay_id ORDER BY ce.charttime ASC) = 1
)

SELECT
  MIN(first_hr) AS min_first_heart_rate
FROM
  heart_rate_first;