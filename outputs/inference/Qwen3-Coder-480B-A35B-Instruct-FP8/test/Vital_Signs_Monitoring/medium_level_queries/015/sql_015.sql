WITH eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.edregtime,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.edregtime IS NOT NULL
),
icu_stays_with_sbp AS (
  SELECT
    icu.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM
    eligible_admissions ea
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON
    ea.hadm_id = icu.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    icu.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    LOWER(di.label) = 'systolic blood pressure'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
  GROUP BY
    icu.stay_id
)
SELECT
  APPROX_QUANTILES(max_sbp, 100)[OFFSET(75)] AS sbp_75th_percentile
FROM
  icu_stays_with_sbp;