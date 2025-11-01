WITH 
-- Identify ICU patients with vasopressors
vasopressor_patients AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    EXTRACT(DAY FROM TIMESTAMP_DIFF(ie.intime, p.admittime, DAY)) AS admission_day,
    ie.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` p ON ie.hadm_id = p.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND ie.intime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 3 DAY)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
      WHERE i.stay_id = ie.stay_id
      AND i.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%Vasopressor%')
      AND i.starttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 3 DAY)
    )
),

-- Calculate 72-hour diagnostic load
diagnostic_load AS (
  SELECT 
    vp.subject_id,
    vp.hadm_id,
    COUNT(DISTINCT 
      CASE 
        WHEN ce.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE category = 'Lab') THEN ce.itemid
        WHEN ie.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE category IN ('Imaging', 'Procedure')) THEN ie.itemid
      END
    ) AS diagnostic_load
  FROM 
    vasopressor_patients vp
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON vp.stay_id = ce.stay_id AND ce.charttime BETWEEN vp.intime AND TIMESTAMP_ADD(vp.intime, INTERVAL 3 DAY)
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` ie ON vp.stay_id = ie.stay_id AND ie.starttime BETWEEN vp.intime AND TIMESTAMP_ADD(vp.intime, INTERVAL 3 DAY)
  GROUP BY 
    vp.subject_id, vp.hadm_id
),

-- Calculate outcomes
outcomes AS (
  SELECT 
    dl.subject_id,
    dl.hadm_id,
    a.hospital_expire_flag,
    a.dischtime,
    a.admittime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_LOS,
    COUNT(DISTINCT p.seq_num) AS procedure_count,
    CASE 
      WHEN ra.readmit_time IS NOT NULL THEN 1 
      ELSE 0 
    END AS readmitted_within_30_days
  FROM 
    diagnostic_load dl
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON dl.hadm_id = a.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON dl.hadm_id = p.hadm_id
  LEFT JOIN (
    SELECT 
      a1.subject_id,
      a1.hadm_id,
      MIN(a2.admittime) AS readmit_time
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a1
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a2 ON a1.subject_id = a2.subject_id
    WHERE 
      a1.dischtime < a2.admittime
      AND a2.admittime BETWEEN TIMESTAMP_ADD(a1.dischtime, INTERVAL 1 DAY) AND TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
    GROUP BY 
      a1.subject_id, a1.hadm_id
  ) ra ON dl.hadm_id = ra.hadm_id
  GROUP BY 
    dl.subject_id, dl.hadm_id, a.hospital_expire_flag, a.dischtime, a.admittime, ra.readmit_time
)

-- Stratify by diagnostic load quartiles and report outcomes
SELECT 
  NTILE(4) OVER (ORDER BY diagnostic_load) AS quartile,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(hospital_LOS) AS avg_hospital_LOS,
  AVG(CAST(hospital_expire_flag AS INT64)) AS in_hospital_mortality_rate,
  AVG(readmitted_within_30_days) AS 30_day_readmission_rate
FROM 
  outcomes o
JOIN 
  diagnostic_load dl ON o.hadm_id = dl.hadm_id
GROUP BY 
  quartile;