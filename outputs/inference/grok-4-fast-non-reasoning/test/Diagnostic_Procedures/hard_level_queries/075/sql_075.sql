WITH cohort AS (
  -- Base cohort: male, 39-49, first ICU stay, DKA diagnosis
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    los,
    first_careunit,
    hospital_expire_flag,
    gender,
    anchor_age
  FROM (
    SELECT 
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.los,
      i.first_careunit,
      a.hospital_expire_flag,
      p.gender,
      p.anchor_age,
      ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
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
      ON i.hadm_id = d.hadm_id
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
      ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 39 AND 49
      AND (
        -- DKA ICD codes (ICD-9: 250.1x; ICD-10: E10.1x, E13.1x)
        (d.icd_version = '9' AND d.icd_code LIKE '250.1%') OR
        (d.icd_version = '10' AND (d.icd_code LIKE 'E10.1%' OR d.icd_code LIKE 'E13.1%'))
      )
  )
  WHERE rn = 1  -- First ICU stay per admission
),

procedure_counts AS (
  -- Distinct procedures in first 24h per stay
  SELECT 
    c.*,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM 
    cohort c
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = CAST(pe.stay_id AS INT64)
    AND pe.starttime >= c.intime
    AND pe.starttime < TIMESTAMP_ADD(c.intime, INTERVAL 1 DAY)
  GROUP BY 
    c.subject_id, c.hadm_id, c.stay_id, c.intime, c.los, c.first_careunit, 
    c.hospital_expire_flag, c.gender, c.anchor_age
)

-- Stratify into quintiles and aggregate
SELECT 
  quintile,
  COUNT(stay_id) AS n_stays,
  ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
  MIN(procedure_count) AS min_procedure_count,
  MAX(procedure_count) AS max_procedure_count,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS hospital_mortality_pct
FROM (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM 
    procedure_counts
)
GROUP BY 
  quintile
ORDER BY 
  quintile;