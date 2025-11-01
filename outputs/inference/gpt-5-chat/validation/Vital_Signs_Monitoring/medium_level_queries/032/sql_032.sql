WITH cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.subject_id = icu.subject_id
    AND a.hadm_id = icu.hadm_id
  -- age at admission
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 53 AND 63
    AND (
      LOWER(icu.first_careunit) LIKE '%stepdown%' 
      OR LOWER(icu.first_careunit) LIKE '%intermediate%'
      OR LOWER(icu.first_careunit) LIKE 'imc%'
    )
    AND icu.stay_id IN (
      SELECT DISTINCT proc.stay_id
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` proc
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON proc.itemid = di.itemid
      WHERE LOWER(di.label) LIKE '%invasive ventilation%'
         OR LOWER(di.label) LIKE '%mechanical ventilation%'
    )
),
sbp_events AS (
  SELECT c.subject_id, c.hadm_id, c.stay_id, ce.charttime, ce.valuenum
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.hadm_id = ce.hadm_id
    AND c.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE 'systolic blood pressure%'
    AND LOWER(di.unitname) = 'mmhg'
    AND ce.valuenum IS NOT NULL
    AND EXTRACT(HOUR FROM ce.charttime) >= 0
    AND EXTRACT(HOUR FROM ce.charttime) < 6
)
SELECT
  STDDEV_SAMP(valuenum) AS sbp_nighttime_stddev_mmhg
FROM sbp_events;