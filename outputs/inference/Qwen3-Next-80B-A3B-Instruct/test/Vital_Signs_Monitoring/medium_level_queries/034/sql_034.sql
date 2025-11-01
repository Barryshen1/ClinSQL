WITH noninvasive_ventilation_stays AS (
  SELECT DISTINCT i.stay_id
  FROM `physionet-data`.mimiciv_3_1_icu.icustays i
  JOIN `physionet-data`.mimiciv_3_1_icu.chartevents ce ON i.stay_id = ce.stay_id
  JOIN `physionet-data`.mimiciv_3_1_icu.d_items d ON ce.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%cpap%' OR LOWER(d.label) LIKE '%bipap%'
),
diastolic_bp_values AS (
  SELECT ce.stay_id, ce.valuenum AS diastolic_bp
  FROM `physionet-data`.mimiciv_3_1_icu.chartevents ce
  JOIN `physionet-data`.mimiciv_3_1_icu.d_items d ON ce.itemid = d.itemid
  WHERE LOWER(d.label) = 'diastolic blood pressure'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 200
),
max_diastolic_per_stay AS (
  SELECT dbp.stay_id, MAX(dbp.diastolic_bp) AS max_diastolic_bp
  FROM diastolic_bp_values dbp
  INNER JOIN noninvasive_ventilation_stays niv ON dbp.stay_id = niv.stay_id
  GROUP BY dbp.stay_id
),
cohort AS (
  SELECT mdp.max_diastolic_bp
  FROM max_diastolic_per_stay mdp
  JOIN `physionet-data`.mimiciv_3_1_icu.icustays i ON mdp.stay_id = i.stay_id
  JOIN `physionet-data`.mimiciv_3_1_hosp.patients p ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
)
SELECT APPROX_QUANTILES(max_diastolic_bp, 100)[OFFSET(25)] AS percentile_25th
FROM cohort;