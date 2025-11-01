WITH female_age_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),
stepdown_imc_admissions AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.transfers`
  WHERE
    LOWER(careunit) LIKE '%stepdown%'
    OR LOWER(careunit) LIKE '%imc%'
),
ventilated_stays AS (
  -- ICU procedureevents: invasive mechanical ventilation
  SELECT DISTINCT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%ventilation%'
    AND (
      LOWER(di.label) LIKE '%invasive%'
      OR LOWER(di.label) LIKE '%mechanical%'
    )
),
qualifying_stays AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN female_age_cohort fac
      ON icu.subject_id = fac.subject_id
      AND icu.hadm_id = fac.hadm_id
    JOIN stepdown_imc_admissions sda
      ON icu.subject_id = sda.subject_id
      AND icu.hadm_id = sda.hadm_id
    JOIN ventilated_stays vs
      ON icu.subject_id = vs.subject_id
      AND icu.hadm_id = vs.hadm_id
      AND icu.stay_id = vs.stay_id
),
sbp_items AS (
  -- Find SBP itemids in mmHg
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    (
      LOWER(label) LIKE '%systolic%'
      AND LOWER(label) LIKE '%blood%'
      AND LOWER(label) LIKE '%pressure%'
    )
    OR LOWER(label) LIKE '%sbp%'
    AND LOWER(unitname) = 'mmhg'
),
nighttime_sbp AS (
  SELECT
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN qualifying_stays qs
      ON ce.subject_id = qs.subject_id
      AND ce.hadm_id = qs.hadm_id
      AND ce.stay_id = qs.stay_id
    JOIN sbp_items si
      ON ce.itemid = si.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND (
      EXTRACT(HOUR FROM ce.charttime) >= 0
      AND EXTRACT(HOUR FROM ce.charttime) < 6
    )
    AND (ce.valueuom = 'mmHg' OR ce.valueuom IS NULL) -- Some SBP may not have valueuom, but d_items already filtered
)
SELECT
  STDDEV_SAMP(valuenum) AS nighttime_sbp_mmHg_stddev
FROM
  nighttime_sbp
;