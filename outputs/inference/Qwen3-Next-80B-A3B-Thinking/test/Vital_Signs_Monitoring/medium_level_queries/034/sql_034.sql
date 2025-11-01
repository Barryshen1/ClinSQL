WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 37 AND 47
),
icustays_filtered AS (
  SELECT i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN patients_filtered p ON i.subject_id = p.subject_id
),
noninvasive_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%CPAP%' OR label LIKE '%BiPAP%'
),
ventilation_stays AS (
  SELECT DISTINCT pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN icustays_filtered i ON pe.stay_id = i.stay_id
  WHERE pe.itemid IN (SELECT itemid FROM noninvasive_itemids)
    AND pe.starttime BETWEEN i.intime AND i.outtime
),
diastolic_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%Diastolic%' OR label LIKE '%DBP%'
),
bp_data AS (
  SELECT 
    c.stay_id,
    MAX(c.valuenum) AS max_diastolic_bp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN ventilation_stays v ON c.stay_id = v.stay_id
  INNER JOIN icustays_filtered i ON c.stay_id = i.stay_id
  WHERE c.itemid IN (SELECT itemid FROM diastolic_itemids)
    AND c.valuenum IS NOT NULL
    AND c.charttime BETWEEN i.intime AND i.outtime
  GROUP BY c.stay_id
)
SELECT 
  PERCENTILE_CONT(max_diastolic_bp, 0.25) AS percentile_25
FROM bp_data;