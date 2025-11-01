WITH eligible_stays AS (
  -- Base ICU stays with patient demographics and admission filters
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn_stay
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND (
      (d.icd_version = 'ICD-9' AND d.icd_code LIKE '493%') OR
      (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'J45%' AND d.icd_code != 'J459') OR  -- Exclude J45.9 if too broad; adjust if needed
      (d.icd_version = 'ICD-10' AND d.icd_code = 'J46')  -- Status asthmaticus
    )
    AND a.admittime <= i.intime  -- Ensure admission before ICU
),
procedure_counts AS (
  -- Count distinct procedure itemids in first 72h, filtered to procedures
  SELECT 
    es.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON es.stay_id = pe.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE 
    es.rn_stay = 1  -- First ICU stay only
    AND pe.starttime <= TIMESTAMP_ADD(es.intime, INTERVAL 72 HOUR)
    AND di.category NOT IN ('Routine Vital Signs', 'Respiratory - Auto-PEEP', 'Respiratory - FiO2')  -- Example filter: exclude monitoring; customize based on d_items review
    AND di.category IS NOT NULL  -- Ensure valid category
    AND pe.itemid IS NOT NULL
  GROUP BY 
    es.stay_id
),
final_data AS (
  -- Join procedure counts back and compute quartiles
  SELECT 
    es.*,
    COALESCE(pc.procedure_count, 0) AS procedure_count,
    DATE_DIFF(es.dischtime, es.admittime, DAY) AS hosp_los_days
  FROM 
    eligible_stays es
  LEFT JOIN 
    procedure_counts pc
    ON es.stay_id = pc.stay_id
  WHERE 
    es.rn_stay = 1
)
SELECT 
  CONCAT('Q', quartile) AS quartile,
  ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(hosp_los_days), 2) AS mean_hospital_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 4) AS mean_mortality
FROM (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM 
    final_data
)
GROUP BY 
  quartile
ORDER BY 
  quartile;