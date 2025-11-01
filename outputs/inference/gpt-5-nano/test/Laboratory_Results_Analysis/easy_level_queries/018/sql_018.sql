WITH abg_pH AS (
  SELECT c.valuenum AS pH_value
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON c.subject_id = icu.subject_id
   AND c.hadm_id = icu.hadm_id
   AND c.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = c.itemid
  WHERE LOWER(p.gender) = 'f'
    AND LOWER(di.label) LIKE '%ph%'
    AND (LOWER(di.category) LIKE '%abg%' OR LOWER(di.category) LIKE '%blood gas%')
    AND c.charttime >= icu.intime
    AND c.charttime <= icu.outtime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY icu.stay_id ORDER BY c.charttime, c.valuenum) = 1
)
SELECT quantiles[OFFSET(50)] AS median_arterial_pH_at_ICU_admission
FROM (
  SELECT APPROX_QUANTILES(pH_value, 100) AS quantiles
  FROM abg_pH
) t;