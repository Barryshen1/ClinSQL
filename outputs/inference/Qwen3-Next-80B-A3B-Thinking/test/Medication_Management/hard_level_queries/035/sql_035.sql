WITH neutropenic_fever AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` le_anc
      WHERE le_anc.subject_id = a.subject_id
        AND le_anc.hadm_id = a.hadm_id
        AND le_anc.itemid = 51300
        AND le_anc.valuenum < 500
        AND le_anc.charttime BETWEEN a.admittime AND a.dischtime
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` le_temp
      WHERE le_temp.subject_id = a.subject_id
        AND le_temp.hadm_id = a.hadm_id
        AND le_temp.itemid = 50800
        AND le_temp.valuenum > 38.0
        AND le_temp.charttime BETWEEN a.admittime AND a.dischtime
    )
),

medication_scores AS (
  SELECT 
    nf.hadm_id,
    COUNT(DISTINCT drug) AS complexity_score
  FROM neutropenic_fever nf
  LEFT JOIN (
    SELECT 
      p.hadm_id,
      p.drug
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.hadm_id = a.hadm_id
    WHERE p.starttime BETWEEN a.admittime AND (a.admittime + INTERVAL '48' HOUR)
    
    UNION ALL
    
    SELECT 
      i.hadm_id,
      di.label AS drug
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
      ON i.itemid = di.itemid
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON i.hadm_id = a.hadm_id
    WHERE i.starttime BETWEEN a.admittime AND (a.admittime + INTERVAL '48' HOUR)
  ) meds ON nf.hadm_id = meds.hadm_id
  GROUP BY nf.hadm_id
),

readmission_flag AS (
  SELECT 
    a1.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a1.subject_id
        AND a2.hadm_id != a1.hadm_id
        AND a2.admittime >= a1.dischtime
        AND a2.admittime <= a1.dischtime + INTERVAL '30' DAY
    ) THEN 1 ELSE 0 END AS readmitted_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
)

SELECT 
  quartile,
  COUNT(*) AS patient_count,
  AVG(complexity_score) AS mean_score,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  AVG(los) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  AVG(readmitted_30d) * 100 AS readmission_percent
FROM (
  SELECT 
    nf.hadm_id,
    nf.hospital_expire_flag,
    nf.los,
    ms.complexity_score,
    rf.readmitted_30d,
    NTILE(4) OVER (ORDER BY ms.complexity_score) AS quartile
  FROM neutropenic_fever nf
  LEFT JOIN medication_scores ms ON nf.hadm_id = ms.hadm_id
  LEFT JOIN readmission_flag rf ON nf.hadm_id = rf.hadm_id
) combined
GROUP BY quartile
ORDER BY quartile;