WITH patient_info AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F' AND 
    p.anchor_age BETWEEN 59 AND 69
),
icu_stays AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays`
),
sbp_records AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum AS sbp
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE 
    ce.itemid = 220050  -- SBP itemid
)
SELECT 
  APPROX_QUANTILES(sbp, 100)[OFFSET(75)] AS percentile_75_sbp
FROM (
  SELECT 
    sr.sbp
  FROM 
    patient_info pi
  JOIN 
    icu_stays si ON pi.hadm_id = si.hadm_id AND pi.subject_id = si.subject_id
  JOIN 
    sbp_records sr ON si.stay_id = sr.stay_id AND si.hadm_id = sr.hadm_id AND pi.subject_id = sr.subject_id
);