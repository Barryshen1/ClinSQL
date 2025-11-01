WITH qualifying_stays AS (
  SELECT 
    ie.stay_id,
    ie.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND (
      pat.anchor_age - (pat.anchor_year - EXTRACT(YEAR FROM adm.admittime))
    ) BETWEEN 66 AND 76
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE 
        pe.stay_id = ie.stay_id
        AND pe.itemid = 225440  -- Intubation procedure
    )
),
sbp_measurements AS (
  SELECT 
    ce.valuenum AS sbp
  FROM qualifying_stays qs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON qs.stay_id = ce.stay_id
  WHERE 
    ce.charttime >= qs.intime
    AND ce.charttime <= DATETIME_ADD(qs.intime, INTERVAL 6 HOUR)
    AND ce.itemid IN (220050, 220179, 225309)  -- Systolic BP itemids
    AND ce.valuenum IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(sbp, 1000)[OFFSET(250)] AS q1,
  APPROX_QUANTILES(sbp, 1000)[OFFSET(750)] AS q3
FROM sbp_measurements;