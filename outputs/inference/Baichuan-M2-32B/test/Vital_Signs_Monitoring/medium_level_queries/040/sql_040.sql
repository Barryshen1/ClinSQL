WITH 
  eligible_patients AS (
    SELECT 
      subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE 
      gender = 'F' 
      AND anchor_age BETWEEN 81 AND 91
  ),
  high_flow_events AS (
    SELECT 
      ce.subject_id,
      ce.hadm_id,
      ce.stay_id,
      ce.charttime
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
      ON ce.itemid = di.itemid
    WHERE 
      di.label LIKE '%high-flow%' OR di.label LIKE '%nasal cannula%'
      AND ce.value IS NOT NULL
  ),
  systolic_bp_items AS (
    SELECT 
      itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE 
      category = 'Vital Signs' 
      AND label LIKE '%Systolic%' 
      AND unitname = 'mm Hg'
  ),
  systolic_bp_events AS (
    SELECT 
      ce.subject_id,
      ce.hadm_id,
      ce.stay_id,
      ce.charttime,
      ce.valuenum AS systolic_bp
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN systolic_bp_items s 
      ON ce.itemid = s.itemid
    WHERE 
      ce.valuenum IS NOT NULL
  ),
  icu_stays_with_high_flow AS (
    SELECT 
      DISTINCT 
      hfe.subject_id,
      hfe.hadm_id,
      hfe.stay_id
    FROM high_flow_events hfe
    INNER JOIN eligible_patients ep 
      ON hfe.subject_id = ep.subject_id
  ),
  per_stay_systolic_means AS (
    SELECT 
      sbe.stay_id,
      AVG(sbe.systolic_bp) AS mean_systolic_bp
    FROM systolic_bp_events sbe
    INNER JOIN icu_stays_with_high_flow ishf 
      ON sbe.stay_id = ishf.stay_id
      AND sbe.subject_id = ishf.subject_id
    GROUP BY sbe.stay_id
  )
SELECT 
  MIN(mean_systolic_bp) AS min_per_stay_mean_systolic_bp
FROM per_stay_systolic_means;