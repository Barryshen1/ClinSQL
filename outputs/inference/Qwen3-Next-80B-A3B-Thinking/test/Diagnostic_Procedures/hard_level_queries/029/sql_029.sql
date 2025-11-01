WITH cohort AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      WHERE 
        ie.stay_id = i.stay_id
        AND ie.itemid IN (221906, 222315, 221289, 221662, 221905)
        AND ie.starttime BETWEEN i.intime AND i.intime + INTERVAL '72' HOUR
    )
),

lab_counts AS (
  SELECT 
    l.hadm_id,
    COUNT(*) AS lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN cohort c ON l.hadm_id = c.hadm_id
  WHERE l.charttime BETWEEN c.intime AND c.intime + INTERVAL '72' HOUR
  GROUP BY l.hadm_id
),

imaging_counts AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN cohort c ON h.hadm_id = c.hadm_id
  WHERE h.chartdate BETWEEN DATE(c.intime) AND DATE(c.intime + INTERVAL '72' HOUR)
  GROUP BY h.hadm_id
),

diagnostic_load AS (
  SELECT 
    c.hadm_id,
    COALESCE(l.lab_count, 0) + COALESCE(i.imaging_count, 0) AS diagnostic_load
  FROM cohort c
  LEFT JOIN lab_counts l ON c.hadm_id = l.hadm_id
  LEFT JOIN imaging_counts i ON c.hadm_id = i.hadm_id
),

procedure_count AS (
  SELECT 
    a.hadm_id,
    COALESCE(p.proc_count, 0) + COALESCE(h.hcpc_count, 0) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN (
    SELECT hadm_id, COUNT(*) AS proc_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    GROUP BY hadm_id
  ) p ON a.hadm_id = p.hadm_id
  LEFT JOIN (
    SELECT hadm_id, COUNT(*) AS hcpc_count
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    GROUP BY hadm_id
  ) h ON a.hadm_id = h.hadm_id
),

los_mortality AS (
  SELECT 
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),

readmission AS (
  SELECT 
    a1.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE 
        a2.subject_id = a1.subject_id
        AND a2.admittime > a1.dischtime
        AND a2.admittime <= a1.dischtime + INTERVAL '30' DAY
    ) THEN 1 ELSE 0 END AS readmission_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
),

quartiles AS (
  SELECT
    dl.hadm_id,
    NTILE(4) OVER (ORDER BY dl.diagnostic_load) AS quartile,
    pc.procedure_count,
    lm.los,
    lm.hospital_expire_flag,
    r.readmission_30d
  FROM diagnostic_load dl
  JOIN procedure_count pc ON dl.hadm_id = pc.hadm_id
  JOIN los_mortality lm ON dl.hadm_id = lm.hadm_id
  JOIN readmission r ON dl.hadm_id = r.hadm_id
)

SELECT
  quartile,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(los) AS avg_los,
  AVG(hospital_expire_flag) AS avg_mortality,
  AVG(readmission_30d) AS avg_readmission_rate
FROM quartiles
GROUP BY quartile
ORDER BY quartile;