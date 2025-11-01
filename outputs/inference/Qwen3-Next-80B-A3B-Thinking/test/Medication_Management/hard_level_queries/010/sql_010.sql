WITH admissions_filtered AS (
  SELECT 
    a.subject_id,  -- Added missing subject_id
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 61 AND 71
),
med_complexity AS (
  SELECT 
    a.hadm_id, 
    COUNT(DISTINCT p.drug) AS complexity_score
  FROM admissions_filtered a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON a.hadm_id = p.hadm_id
    AND p.starttime BETWEEN a.admittime AND a.admittime + INTERVAL '24' HOUR
  GROUP BY a.hadm_id
),
readmission_status AS (
  SELECT 
    a.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a.subject_id
        AND a2.admittime >= a.dischtime
        AND a2.admittime <= a.dischtime + INTERVAL '30' DAY
        AND a2.hadm_id != a.hadm_id
    ) THEN 1 ELSE 0 END AS readmitted_30d
  FROM admissions_filtered a
),
quintiles AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    m.complexity_score,
    r.readmitted_30d,
    NTILE(5) OVER (ORDER BY m.complexity_score) AS quintile
  FROM admissions_filtered a
  JOIN med_complexity m ON a.hadm_id = m.hadm_id
  JOIN readmission_status r ON a.hadm_id = r.hadm_id
)
SELECT
  quintile,
  COUNT(*) AS num_patients,
  AVG(complexity_score) AS mean_complexity_score,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los,
  AVG(hospital_expire_flag) AS in_hospital_mortality,
  AVG(readmitted_30d) AS thirty_day_readmission_rate
FROM quintiles
GROUP BY quintile
ORDER BY quintile;