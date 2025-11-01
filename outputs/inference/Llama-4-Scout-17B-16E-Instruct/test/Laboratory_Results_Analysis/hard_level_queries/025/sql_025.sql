WITH 
-- Identify hemorrhagic stroke patients
hemorrhagic_stroke_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.icd_code IN (
      SELECT 
        icd_code 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
      WHERE 
        long_title LIKE '%Hemorrhagic stroke%'
    )
),

-- Identify critical lab values within 72 hours
critical_labs AS (
  SELECT 
    h.hadm_id, 
    COUNT(DISTINCT CASE 
      WHEN 
        l.valueuom IS NOT NULL 
        AND l.valuenum < dl.ref_range_lower 
      THEN 1 
      ELSE NULL 
    END) + 
    COUNT(DISTINCT CASE 
      WHEN 
        l.valueuom IS NOT NULL 
        AND l.valuenum > dl.ref_range_upper 
      THEN 1 
      ELSE NULL 
    END) AS critical_lab_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN 
    hemorrhagic_stroke_patients h 
      ON l.hadm_id = h.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl 
      ON l.itemid = dl.itemid
  WHERE 
    l.charttime BETWEEN h.admittime AND TIMESTAMP_ADD(h.admittime, INTERVAL 3 DAY)
  GROUP BY 
    h.hadm_id
),

-- Calculate 90th percentile of lab-instability scores
lab_instability_p90 AS (
  SELECT 
    APPROX_QUANTILES(critical_lab_count, 0.9)[OFFSET(1)] AS p90
  FROM 
    critical_labs
)

-- Patient outcomes for those with lab-instability score >= P90
SELECT 
  COUNT(DISTINCT h.hadm_id) AS patients_count,
  SUM(CASE 
    WHEN 
      p.dod IS NOT NULL 
    THEN 1 
    ELSE 0 
  END) / COUNT(DISTINCT h.hadm_id) AS mortality,
  AVG(DATEDIFF(a.dischtime, h.admittime)) AS mean_los,
  AVG(cl.critical_lab_count) AS avg_critical_labs
FROM 
  hemorrhagic_stroke_patients h
JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON h.hadm_id = a.hadm_id
JOIN 
  critical_labs cl 
    ON h.hadm_id = cl.hadm_id
CROSS JOIN 
  lab_instability_p90 p90
WHERE 
  cl.critical_lab_count >= p90.p90
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON h.subject_id = p.subject_id;