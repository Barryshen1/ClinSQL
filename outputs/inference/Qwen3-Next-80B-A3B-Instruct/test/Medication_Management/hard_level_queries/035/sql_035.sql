WITH neutropenic_fever_patients AS (
  SELECT DISTINCT
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
      WHERE le.subject_id = i.subject_id
        AND le.itemid = 51300  -- ANC
        AND le.valuenum < 500
        AND le.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE ce.stay_id = i.stay_id
        AND ce.itemid = 223762  -- Temperature Celsius
        AND ce.valuenum > 38.3
        AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
    )
),

medication_complexity AS (
  SELECT
    nfp.stay_id,
    COUNT(DISTINCT p.drug) AS med_count
  FROM neutropenic_fever_patients nfp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON nfp.hadm_id = p.hadm_id
    AND p.starttime >= nfp.intime
    AND p.starttime < TIMESTAMP_ADD(nfp.intime, INTERVAL 48 HOUR)
  GROUP BY nfp.stay_id
),

quartiles AS (
  SELECT
    mc.stay_id,
    mc.med_count,
    NTILE(4) OVER (ORDER BY mc.med_count) AS quartile,
    nfp.los,
    nfp.subject_id,  -- Added missing subject_id
    a.hospital_expire_flag,
    a.dischtime
  FROM medication_complexity mc
  INNER JOIN neutropenic_fever_patients nfp ON mc.stay_id = nfp.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON nfp.hadm_id = a.hadm_id
),

readmission AS (
  SELECT
    q.stay_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM quartiles q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON q.subject_id = a2.subject_id
    AND a2.admittime > q.dischtime
    AND a2.admittime <= TIMESTAMP_ADD(q.dischtime, INTERVAL 30 DAY)
)

SELECT
  quartile,
  COUNT(*) AS patient_count,
  AVG(med_count) AS mean_med_complexity,
  MIN(med_count) AS min_med_complexity,
  MAX(med_count) AS max_med_complexity,
  AVG(los) AS mean_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent,
  AVG(CAST(readmitted_30d AS FLOAT64)) * 100 AS readmission_30d_percent
FROM quartiles q
LEFT JOIN readmission r ON q.stay_id = r.stay_id
GROUP BY quartile
ORDER BY quartile;