WITH male_icu_stays AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
),
first_sodium AS (
  SELECT 
    m.stay_id,
    l.valuenum
  FROM male_icu_stays m
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON m.hadm_id = l.hadm_id
    AND l.charttime >= m.intime
    AND l.charttime <= m.outtime
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE d.label = 'SODIUM'
    AND d.fluid = 'Blood'
    AND l.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY m.stay_id 
    ORDER BY l.charttime, l.labevent_id
  ) = 1
)
SELECT 
  APPROX_QUANTILES(valuenum, 1000)[SAFE_OFFSET(750)] 
  - APPROX_QUANTILES(valuenum, 1000)[SAFE_OFFSET(250)] AS iqr
FROM first_sodium;