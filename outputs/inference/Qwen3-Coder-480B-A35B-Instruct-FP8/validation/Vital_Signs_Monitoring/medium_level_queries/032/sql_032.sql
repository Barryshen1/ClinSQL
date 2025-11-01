WITH cohort AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    p.subject_id = i.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND LOWER(i.first_careunit) IN ('sdu', 'imc')
),
ventilated AS (
  SELECT DISTINCT
    c.stay_id
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  ON
    c.stay_id = pe.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    pe.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%invasive%vent%'
),
sbp_measurements AS (
  SELECT
    c.subject_id,
    c.stay_id,
    ce.valuenum AS sbp
  FROM
    cohort c
  JOIN
    ventilated v
  ON
    c.stay_id = v.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    c.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE 'systolic%'
    AND LOWER(ce.valueuom) = 'mmhg'
    AND ce.valuenum IS NOT NULL
    AND EXTRACT(HOUR FROM ce.charttime) BETWEEN 0 AND 5
)
SELECT
  STDDEV_POP(sbp) AS sbp_stddev
FROM
  sbp_measurements;