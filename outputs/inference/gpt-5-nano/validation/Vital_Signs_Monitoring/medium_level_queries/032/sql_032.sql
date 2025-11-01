WITH eligible_subjects AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON p.subject_id = i.subject_id
  WHERE LOWER(p.gender) IN ('female', 'f')
    AND p.anchor_age BETWEEN 53 AND 63
    AND (
      LOWER(i.first_careunit) IN ('imc', 'stepdown', 'step down', 'step-down')
      OR LOWER(i.last_careunit) IN ('imc', 'stepdown', 'step down', 'step-down')
    )
),
ventilated_stays AS (
  SELECT DISTINCT i.subject_id, i.hadm_id, i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN eligible_subjects AS es
    ON i.subject_id = es.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    WHERE pe.subject_id = i.subject_id
      AND pe.hadm_id = i.hadm_id
      AND pe.stay_id = i.stay_id
      AND (
        LOWER(pe.ordercategorydescription) LIKE '%intubation%'
        OR LOWER(pe.ordercategorydescription) LIKE '%ventilation%'
      )
  )
),
sbp_readings AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  JOIN ventilated_stays AS vs
    ON ce.subject_id = vs.subject_id
   AND ce.hadm_id = vs.hadm_id
   AND ce.stay_id = vs.stay_id
  WHERE LOWER(di.label) LIKE '%systolic%'
    AND LOWER(di.label) LIKE '%blood%'  -- target SBP readings
    AND EXTRACT(TIME FROM ce.charttime) BETWEEN TIME '00:00:00' AND TIME '06:00:00'
)
SELECT STDDEV_SAMP(valuenum) AS sbp_stddev_mmHg
FROM sbp_readings;