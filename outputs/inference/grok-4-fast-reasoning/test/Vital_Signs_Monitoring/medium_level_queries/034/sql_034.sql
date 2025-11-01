WITH eligible_stays AS (
  SELECT DISTINCT i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce_niv
      WHERE ce_niv.subject_id = i.subject_id
        AND ce_niv.stay_id = i.stay_id
        AND ce_niv.itemid = 223848
        AND ce_niv.value IN ('CPAP', 'BIPAP')
    )
),
max_dias_per_stay AS (
  SELECT 
    es.stay_id,
    MAX(ce.valuenum) AS max_dias
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = es.stay_id
  WHERE ce.itemid IN (220180, 2202)
    AND ce.valuenum IS NOT NULL
  GROUP BY es.stay_id
  HAVING max_dias IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(max_dias, 4)[OFFSET(1)] AS p25_max_diastolic_bp
FROM max_dias_per_stay;