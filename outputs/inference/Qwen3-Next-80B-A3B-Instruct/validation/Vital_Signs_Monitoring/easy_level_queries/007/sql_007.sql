WITH first_icu_stay AS (
  SELECT 
    hadm_id,
    stay_id,
    intime,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime ASC) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays
),
respiratory_rate_first AS (
  SELECT 
    p.subject_id,
    ce.valuenum,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY ce.charttime ASC) AS rn_first_rr
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a 
    ON p.subject_id = a.subject_id
  INNER JOIN first_icu_stay fis 
    ON a.hadm_id = fis.hadm_id AND fis.rn = 1
  INNER JOIN physionet-data.mimiciv_3_1_icu.chartevents ce 
    ON fis.stay_id = ce.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di 
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND di.label = 'Respiratory Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= a.admittime  -- Ensure measurement is at or after admission
)
SELECT 
  STDDEV_POP(valuenum) AS std_dev_first_respiratory_rate
FROM respiratory_rate_first
WHERE rn_first_rr = 1;