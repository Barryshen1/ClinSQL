WITH female_adms AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),

stepdown_icus AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id
  FROM
    female_adms AS f
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
      USING (subject_id, hadm_id)
  WHERE
    (ic.first_careunit LIKE '%STEP%' OR ic.first_careunit LIKE '%IMC%')
),

ventilator_stays AS (
  SELECT DISTINCT
    s.subject_id,
    s.hadm_id,
    s.stay_id
  FROM
    stepdown_icus AS s
    JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
      ON pe.subject_id = s.subject_id
     AND pe.hadm_id    = s.hadm_id
     AND pe.stay_id    = s.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON di.itemid = pe.itemid
  WHERE
    LOWER(di.label) LIKE '%ventilation%'
    AND LOWER(CAST(pe.value AS STRING)) = 'invasive'
),

night_sbps AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum AS sbp
  FROM
    ventilator_stays AS v
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON ce.subject_id = v.subject_id
     AND ce.hadm_id    = v.hadm_id
     AND ce.stay_id    = v.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di_sb
      ON di_sb.itemid = ce.itemid
  WHERE
    di_sb.label LIKE '%Systolic%'
    AND ce.valueuom = 'mmHg'
    AND ce.valuenum IS NOT NULL
    AND TIME(ce.charttime) BETWEEN '00:00:00' AND '06:00:00'
)

SELECT
  STDDEV_SAMP(sbp) AS nighttime_sbp_sd_mmHg
FROM
  night_sbps;