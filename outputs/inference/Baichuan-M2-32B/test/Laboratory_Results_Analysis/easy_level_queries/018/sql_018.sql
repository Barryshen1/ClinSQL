WITH first_icu_stay AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE intime IS NOT NULL
),
female_patients AS (
  SELECT 
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
),
abg_ph_item AS (
  SELECT 50809 AS itemid
)
SELECT 
  fp.subject_id,
  fis.hadm_id,
  fis.stay_id,
  fis.intime,
  APPROX_QUANTILES(le.valuenum, 100)[SAFE_OFFSET(50)] AS median_ph
FROM female_patients fp
JOIN first_icu_stay fis 
  ON fp.subject_id = fis.subject_id AND fis.rn = 1
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
  ON fis.subject_id = le.subject_id 
  AND le.charttime BETWEEN fis.intime AND TIMESTAMP_ADD(fis.intime, INTERVAL 6 HOUR)
JOIN abg_ph_item abi 
  ON le.itemid = abi.itemid
GROUP BY fp.subject_id, fis.hadm_id, fis.stay_id, fis.intime;