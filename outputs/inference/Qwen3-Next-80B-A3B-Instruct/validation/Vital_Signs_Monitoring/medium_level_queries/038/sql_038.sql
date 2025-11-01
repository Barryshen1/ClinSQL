WITH ventilated_patients AS (
  SELECT DISTINCT i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND (LOWER(di.label) LIKE '%intubation%' OR LOWER(di.label) LIKE '%invasive ventilation%')
    AND pe.starttime BETWEEN i.intime AND i.outtime
),
sbp_measurements AS (
  SELECT ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN ventilated_patients vp
    ON ce.stay_id = vp.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%systolic%'
    AND ce.charttime BETWEEN vp.intime AND TIMESTAMP_ADD(vp.intime, INTERVAL 6 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 50 AND 250
)
SELECT 
  APPROX_QUANTILES(sbp.valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(sbp.valuenum, 4)[OFFSET(1)] AS iqr_systolic_bp
FROM sbp_measurements sbp;