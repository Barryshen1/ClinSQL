WITH patient_cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON a.hadm_id = icu.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
    ON icu.stay_id = pe.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON pe.itemid = di.itemid
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 53 AND 63
    AND (
      LOWER(icu.first_careunit) LIKE '%step%' 
      OR LOWER(icu.first_careunit) LIKE '%imc%'
      OR LOWER(icu.last_careunit) LIKE '%step%'
      OR LOWER(icu.last_careunit) LIKE '%imc%'
    )
    AND LOWER(di.label) LIKE '%invasive ventilation%'
),
systolic_bp_night AS (
  SELECT ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN patient_cohort pc
    ON ce.subject_id = pc.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON ce.stay_id = icu.stay_id
  WHERE LOWER(di.label) = 'arterial bp [systolic]'
    AND ce.valuenum IS NOT NULL
    AND ce.valueuom = 'mm Hg'
    AND ce.charttime >= icu.intime
    AND ce.charttime <= icu.outtime
    AND EXTRACT(HOUR FROM ce.charttime) BETWEEN 0 AND 5
)
SELECT STDDEV(valuenum) AS sbp_night_stddev
FROM systolic_bp_night;